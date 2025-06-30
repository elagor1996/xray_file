#!/bin/sh

echo "🔧 Обновляем список пакетов..."
opkg update

# Установим зависимости
DEPS="ipset iptables iptables-legacy iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat wget binutils tar"

echo "🔍 Проверяем и устанавливаем зависимости..."
for pkg in $DEPS; do
  if ! opkg list-installed | grep -qw "$pkg"; then
    echo "📦 Устанавливаем $pkg..."
    opkg install "$pkg"
    [ $? -eq 0 ] && echo "✅ $pkg установлен" || { echo "❌ Ошибка установки $pkg"; exit 1; }
  else
    echo "✅ $pkg уже установлен"
  fi
done

# Настроим BASE_URL
BASE_URL="https://github.com/elagor1996/xray_file/raw/main/passwall"

# dnsmasq
echo "🔧 Проверяем dnsmasq..."
if opkg list-installed | grep -qw "^dnsmasq\s"; then
  echo "🧹 Удаляем обычный dnsmasq..."
  opkg remove dnsmasq --force-depends --force-remove
  rm -f /etc/hotplug.d/ntp/25-dnsmasqsec \
        /etc/init.d/dnsmasq \
        /usr/lib/dnsmasq/dhcp-script.sh \
        /usr/sbin/dnsmasq \
        /usr/share/acl.d/dnsmasq_acl.json \
        /usr/share/dnsmasq/dhcpbogushostname.conf \
        /usr/share/dnsmasq/rfc6761.conf
  echo "✅ dnsmasq удалён (или попытка сделана)"
else
  echo "✅ dnsmasq не установлен"
fi

# dnsmasq-full
echo "📦 Устанавливаем dnsmasq-full..."
opkg install dnsmasq-full
[ $? -eq 0 ] && echo "✅ dnsmasq-full установлен" || { echo "❌ Ошибка установки dnsmasq-full"; exit 1; }

# Скачать список файлов
echo "📥 Загружаем список пакетов с $BASE_URL/_files.txt"
wget -O /tmp/_files.txt "$BASE_URL/_files.txt" || { echo "❌ Ошибка загрузки _files.txt"; exit 1; }

# Ставим пакеты
echo "📦 Устанавливаем пакеты из списка..."
grep -v '^\s*#' /tmp/_files.txt | while read -r file; do
  [ -z "$file" ] && continue
  echo "⬇️ Скачиваем $file"
  wget -O "/tmp/$file" "$BASE_URL/$file" || { echo "❌ Ошибка скачивания $file"; continue; }
  echo "🚀 Устанавливаем $file"
  opkg install "/tmp/$file" || echo "⚠️ Ошибка установки $file"
done

# Геофайлы: ставим в /usr/share/v2ray
echo "📂 Подготавливаем /usr/share/v2ray..."
mkdir -p /usr/share/v2ray

echo "⬇️ Загружаем geoip.dat..."
wget -O /usr/share/v2ray/geoip.dat "$BASE_URL/geoip.dat" && echo "✅ geoip.dat загружен" || echo "❌ Ошибка загрузки geoip.dat"

echo "⬇️ Загружаем geosite.dat..."
wget -O /usr/share/v2ray/geosite.dat "$BASE_URL/geosite.dat" && echo "✅ geosite.dat загружен" || echo "❌ Ошибка загрузки geosite.dat"

# UCI конфиг
echo "🔧 Настраиваем пути для Passwall"
uci set passwall.@global[0].xray_bin='/tmp/xray/usr/bin/xray'
uci set passwall.@global[0].geoview_bin='/tmp/geoview/usr/bin/geoview'
uci set passwall.@global[0].geo_data_path='/usr/share/v2ray'
uci set passwall.@global[0].use_direct_list='1'
uci set passwall.@global[0].use_proxy_list='1'
uci set passwall.@global[0].use_block_list='0'
uci set passwall.@global[0].tcp_proxy_mode='disable'
uci set passwall.@global[0].udp_proxy_mode='disable'
uci commit passwall
echo "✅ Конфигурация Passwall обновлена"

# Символические ссылки
echo "🔗 Создаём ссылки..."
ln -sf /tmp/xray/usr/bin/xray /usr/bin/xray
ln -sf /tmp/geoview/usr/bin/geoview /usr/bin/geoview
echo "✅ Ссылки готовы"

# Настройка автозапуска обновления
UPDATE_SCRIPT="/usr/bin/xray_geoview_update.sh"
STARTUP_SCRIPT="/etc/init.d/xray_geoview_update"

echo "🔄 Настраиваем автообновление Xray и Geoview"

if [ ! -f "$UPDATE_SCRIPT" ]; then
  echo "⬇️ Скачиваем $UPDATE_SCRIPT"
  wget -O "$UPDATE_SCRIPT" "https://github.com/elagor1996/xray_file/raw/main/xray_geoview_update.sh" \
    && chmod +x "$UPDATE_SCRIPT" \
    && echo "✅ Скрипт обновления загружен" \
    || echo "❌ Не удалось скачать скрипт обновления"
else
  echo "✅ Скрипт обновления уже существует"
fi

# init.d для автозапуска
if [ ! -f "$STARTUP_SCRIPT" ]; then
  echo "⚙️ Создаём автозапуск"
  cat << 'EOF' > "$STARTUP_SCRIPT"
#!/bin/sh /etc/rc.common
START=95
start() {
  /usr/bin/xray_geoview_update.sh
}
EOF
  chmod +x "$STARTUP_SCRIPT"
  /etc/init.d/xray_geoview_update enable
  echo "✅ Автозапуск настроен"
else
  echo "✅ Автозапуск уже существует"
fi

# Перезапускаем passwall
echo "🔄 Перезапускаем Passwall"
/etc/init.d/passwall restart

echo "🚀 Перезагружаем роутер"
/sbin/reboot

exit 0
