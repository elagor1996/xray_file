#!/bin/sh

logger -t passwall-init "⏳ Ожидаем доступности сети..."

count=0
while ! ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; do
  sleep 1
  count=$((count+1))
  if [ $count -ge 30 ]; then
    logger -t passwall-init "⚠️ Сеть недоступна после 30 секунд ожидания, продолжаем..."
    break
  fi
done

# Xray
if [ ! -x /tmp/xray/usr/bin/xray ]; then
  logger -t passwall-init "⬇️ Скачиваем xray-core..."
  mkdir -p /tmp/xray
  wget -q -O /tmp/xray-core.ipk "https://github.com/elagor1996/xray_file/raw/main/passwall/xray-core_25.6.8-1_mipsel_24kc.ipk"
  logger -t passwall-init "📦 Распаковываем xray-core..."
  tar -xvf /tmp/xray-core.ipk -C /tmp
  tar -xzf /tmp/data.tar.gz -C /tmp/xray
  chmod +x /tmp/xray/usr/bin/xray
  rm -f /tmp/xray-core.ipk /tmp/data.tar.gz
else
  logger -t passwall-init "✅ xray-core уже установлен, скачивание пропущено"
fi

uci set passwall.@global[0].xray_bin='/tmp/xray/usr/bin/xray'

# Geoview
if [ ! -x /tmp/geoview/usr/bin/geoview ]; then
  logger -t passwall-init "⬇️ Скачиваем geoview..."
  mkdir -p /tmp/geoview
  wget -q -O /tmp/geoview.ipk "https://github.com/elagor1996/xray_file/raw/main/passwall/geoview_0.1.10-1_mipsel_24kc.ipk"
  logger -t passwall-init "📦 Распаковываем geoview..."
  tar -xvf /tmp/geoview.ipk -C /tmp
  tar -xzf /tmp/data.tar.gz -C /tmp/geoview
  chmod +x /tmp/geoview/usr/bin/geoview
  rm -f /tmp/geoview.ipk /tmp/data.tar.gz
else
  logger -t passwall-init "✅ geoview уже установлен, скачивание пропущено"
fi

uci set passwall.@global[0].geoview_bin='/tmp/geoview/usr/bin/geoview'

# Включаем Passwall и коммитим конфигурацию
uci set passwall.@global[0].enabled='1'
uci commit passwall

sleep 1

logger -t passwall-init "Перезапуск passwall (первый)..."
/etc/init.d/passwall restart

sleep 2

logger -t passwall-init "Перезапуск passwall (второй) для надёжности..."
/etc/init.d/passwall restart

logger -t passwall-init "✅ Xray и Geoview установлены, Passwall перезапущен"
