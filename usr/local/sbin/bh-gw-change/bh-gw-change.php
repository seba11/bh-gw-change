<?php
// bh-gw-change.php
$INSTALL_DIR = "/usr/local/sbin/bh-gw-change";
$OUT_IFACE = exec("$INSTALL_DIR/config_vars.sh INTERNET_ETH");
$SNAT_IP = exec("$INSTALL_DIR/config_vars.sh INTERNET_IP");

$method = $_SERVER['REQUEST_METHOD'];

preg_match('/\/(\d{1,3}\.\d{1,3}.\d{1,3}.\d{1,3})/', $_SERVER["REQUEST_URI"], $match);
if (preg_match('/\/(\d{1,3}\.\d{1,3}.\d{1,3}.\d{1,3})/', $_SERVER["REQUEST_URI"], $match))
  $ip = $match[1];
else
  return false;

switch ($method) {

  case 'PUT':
        exec("iptables -t nat -D POSTROUTING -o $OUT_IFACE -m set --match-set snat-$ip src -j SNAT --to-source $ip", $out, $rcode);
        echo $rcode.PHP_EOL;
        if ($rcode) return false;

        exec("iptables -t nat -A POSTROUTING -o $OUT_IFACE -m set --match-set snat-$ip src -j SNAT --to-source $SNAT_IP", $out, $rcode);
        echo $rcode.PHP_EOL;
        if ($rcode) return false;

        error_log("Changed SNAT for $ip to $SNAT_IP");
        break;

  case 'DELETE':
        exec("iptables -t nat -D POSTROUTING -o $OUT_IFACE -m set --match-set snat-$ip src -j SNAT --to-source $SNAT_IP", $out, $rcode);
        echo $rcode.PHP_EOL;
        if ($rcode) return false;

        exec("iptables -t nat -A POSTROUTING -o $OUT_IFACE -m set --match-set snat-$ip src -j SNAT --to-source $ip", $out, $rcode);
        echo $rcode.PHP_EOL;
        if ($rcode) return false;

        error_log("Recovered SNAT for $ip");
        break;

  default:
        return false;
}

return true;