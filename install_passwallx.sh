#!/bin/sh

echo "🔧 Обновляем список пакетов..."
opkg update

DEPS="ipset iptables iptables-legacy iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat wget binutils tar"

echo "🔍 Проверяем и устанавливаем отсутствующие зависимости..."
for pkg in $DEPS; do
  if ! opkg list-installed | grep -qw "$pkg"; then
    echo "📦 Устанавливаем $pkg..."
    opkg install "$pkg"
    if [ $? -ne 0 ]; then
      echo "❌ Ошибка установки $pkg"
      exit 1
    else
      echo "✅ $pkg установлен"
    fi
  else
    echo "✅ $pkg уже установлен"
  fi
done

BASE_URL="https://github.com/elagor1996/xray_file/raw/main/passwall"

echo "🔧 Проверяем, установлен ли обычный dnsmasq..."
if opkg list-installed | grep -qw "^dnsmasq\s"; then
  echo "🔧 Удаляем стандартный dnsmasq и очищаем конфликтующие файлы..."

  opkg remove dnsmasq --force-depends --force-remove
  if [ $? -ne 0 ]; then
    echo "⚠️ Ошибка при удалении dnsmasq, пытаемся продолжить..."
  fi

  rm -f /etc/hotplug.d/ntp/25-dnsmasqsec \
        /etc/init.d/dnsmasq \
        /usr/lib/dnsmasq/dhcp-script.sh \
        /usr/sbin/dnsmasq \
        /usr/share/acl.d/dnsmasq_acl.json \
        /usr/share/dnsmasq/dhcpbogushostname.conf \
        /usr/share/dnsmasq/rfc6761.conf

  echo "Проверяем, остался ли пакет dnsmasq..."
  if opkg list-installed | grep -qw "^dnsmasq\s"; then
    echo "❌ dnsmasq не удалось удалить полностью!"
    opkg whatdepends dnsmasq || echo "⚠️ Не удалось определить зависимости"
    exit 1
  else
    echo "✅ dnsmasq удалён"
  fi
else
  echo "✅ Обычный dnsmasq не установлен, пропускаем удаление"
fi

echo "📦 Устанавливаем dnsmasq-full, если не установлен..."
if ! opkg list-installed | grep -qw "dnsmasq-full"; then
  opkg install dnsmasq-full
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка установки dnsmasq-full"
    exit 1
  else
    echo "✅ dnsmasq-full установлен"
  fi
else
  echo "✅ dnsmasq-full уже установлен"
fi

echo "🎯 Загружаем список пакетов из $BASE_URL/_files.txt..."
wget -qO /tmp/_files.txt "$BASE_URL/_files.txt"
if [ $? -ne 0 ]; then
  echo "❌ Ошибка загрузки списка файлов"
  exit 1
fi

echo "📦 Устанавливаем пакеты из списка (без xray-core)..."

grep -v '^\s*#' /tmp/_files.txt | while read -r filename; do
  [ -z "$filename" ] && continue

  echo "⬇️ Скачиваем '$filename'..."
  wget -qO "/tmp/$filename" "$BASE_URL/$filename"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка скачивания $filename"
    continue
  fi

  echo "📦 Устанавливаем $filename..."
  opkg install "/tmp/$filename"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка установки $filename"
  else
    echo "✅ $filename установлен успешно"
  fi
done

echo "📂 Создаём папку /tmp/v2ray для геофайлов..."
mkdir -p /tmp/v2ray

echo "⬇️ Загружаем geosite.dat..."
wget -qO /tmp/v2ray/geosite.dat https://github.com/elagor1996/xray_file/raw/main/passwall/geosite.dat
if [ $? -ne 0 ]; then
  echo "❌ Ошибка загрузки geosite.dat"
else
  echo "✅ geosite.dat загружен"
fi

echo "🔄 Обновляем пути бинарников и geo_data_path в UCI..."
uci set passwall.@global[0].xray_bin='/tmp/xray/usr/bin/xray'
uci set passwall.@global[0].geoview_bin='/tmp/geoview/usr/bin/geoview'
uci set passwall.@global[0].geo_data_path='/tmp/v2ray'

# Добавляем новые параметры proxy/direct/block и режимы tcp/udp
uci set passwall.@global[0].use_direct_list='0'
uci set passwall.@global[0].use_proxy_list='0'
uci set passwall.@global[0].use_block_list='0'

uci set passwall.@global[0].tcp_proxy_mode='disable'
uci set passwall.@global[0].udp_proxy_mode='disable'

uci commit passwall
echo "✅ Пути и параметры прокси обновлены"

echo "🔗 Создаём символические ссылки в /usr/bin для удобства..."
ln -sf /tmp/xray/usr/bin/xray /usr/bin/xray
ln -sf /tmp/geoview/usr/bin/geoview /usr/bin/geoview
echo "✅ Символические ссылки созданы"

# Настройка автозапуска скрипта обновления xray_geoview_update.sh
STARTUP_SCRIPT="/etc/init.d/xray_geoview_update"
UPDATE_SCRIPT="/usr/bin/xray_geoview_update.sh"

echo "🔄 Настраиваем автозапуск скрипта обновления Xray и Geoview..."

if [ ! -f "$UPDATE_SCRIPT" ]; then
  echo "⬇️ Скачиваем скрипт обновления xray_geoview_update.sh..."
  if wget -qO "$UPDATE_SCRIPT" "$BASE_URL/xray_geoview_update.sh"; then
    chmod +x "$UPDATE_SCRIPT"
    echo "✅ Скрипт обновления скачан и права выставлены"
  else
    echo "❌ Ошибка скачивания скрипта обновления"
  fi
fi

if [ ! -f "$STARTUP_SCRIPT" ]; then
  cat << 'EOF' > "$STARTUP_SCRIPT"
#!/bin/sh /etc/rc.common
START=95
start() {
  /usr/bin/xray_geoview_update.sh
}
EOF
  chmod +x "$STARTUP_SCRIPT"
  /etc/init.d/xray_geoview_update enable
  echo "✅ Автозапуск создан и включён"
else
  echo "✅ Автозапуск уже существует"
fi

echo "🔄 Перезапускаем Passwall для применения настроек..."
/etc/init.d/passwall restart

echo "🔄 Перезагрузка роутера для применения всех изменений..."
reboot

exit 0
