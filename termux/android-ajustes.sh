#!/system/bin/sh
# Ajustes do Android para o Termux não ser morto em segundo plano. Roda no shell do sistema:
#   do PC:     adb shell sh < termux/android-ajustes.sh
#   no celular com Shizuku: RISH_APPLICATION_ID=com.termux sh ~/bin/rish -c "sh …/android-ajustes.sh"
# Idempotente. Para desfazer o item 1: device_config put activity_manager max_phantom_processes 32
#   e settings put global settings_enable_monitor_phantom_procs true
ok() { echo "ok    $*"; }
falha() { echo "FALHA $*"; }

# 1. "Phantom process killer" (Android 12+): sem isso, o Android mata as abas do Termux juntas.
device_config set_sync_disabled_for_tests persistent 2>/dev/null
device_config put activity_manager max_phantom_processes 2147483647
settings put global settings_enable_monitor_phantom_procs false
[ "$(device_config get activity_manager max_phantom_processes)" = 2147483647 ] \
  && ok "processos do Termux não são mais mortos em lote" || falha "phantom process killer"

# 2. Sem otimização de bateria e liberados em segundo plano.
for p in com.termux com.termux.boot com.termux.api com.tailscale.ipn moe.shizuku.privileged.api; do
  pm path "$p" >/dev/null 2>&1 || { echo "--    $p não instalado"; continue; }
  dumpsys deviceidle whitelist +"$p" >/dev/null
  cmd appops set "$p" RUN_IN_BACKGROUND allow
  cmd appops set "$p" RUN_ANY_IN_BACKGROUND allow
  cmd appops set "$p" WAKE_LOCK allow
  ok "$p sem restrição de bateria"
done

# 3. Tailscale como VPN sempre ativa (volta sozinho após reboot), sem bloquear a internet se cair.
if pm path com.tailscale.ipn >/dev/null 2>&1; then
  settings put secure always_on_vpn_app com.tailscale.ipn && settings put secure always_on_vpn_lockdown 0 \
    && ok "Tailscale = VPN sempre ativa" || falha "VPN sempre ativa"
fi
pm path com.termux.boot >/dev/null 2>&1 || echo "FALTA  Termux:Boot (mesma origem do Termux: F-Droid ou GitHub)"
