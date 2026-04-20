{ lib, ... }:

let
  # ── Thunderbolt point-to-point links ────────────────────────────────────
  # Each cable is a /30 subnet between two (host, interface) endpoints.
  # Side "a" gets .1, side "b" gets .2.  No L2 bridging — pure L3.
  thunderboltLinks = [
    {
      subnet = "10.99.3"; # 10.99.3.0/30
      a = {
        host = "CK2Q9LN7PM-MBA";
        iface = "en1";
      };
      b = {
        host = "GJHC5VVN49-MBP";
        iface = "en2";
      };
    }
  ];

  thunderboltHosts = lib.unique (
    [
      "GN9CFLM92K-MBP"
      "L75T4YHXV7-MBA"
    ]
    ++ lib.concatMap (link: [
      link.a.host
      link.b.host
    ]) thunderboltLinks
  );

  exoPort = 52416;

  linksForHost =
    hostname:
    lib.concatMap (
      link:
      if link.a.host == hostname then
        [
          {
            ip = "${link.subnet}.1";
            peerIp = "${link.subnet}.2";
            peerHost = link.b.host;
            iface = link.a.iface;
            subnet = link.subnet;
          }
        ]
      else if link.b.host == hostname then
        [
          {
            ip = "${link.subnet}.2";
            peerIp = "${link.subnet}.1";
            peerHost = link.a.host;
            iface = link.b.iface;
            subnet = link.subnet;
          }
        ]
      else
        [ ]
    ) thunderboltLinks;

  exoPeersFor =
    hostname:
    let
      links = linksForHost hostname;
    in
    map (l: "/ip4/${l.peerIp}/tcp/${toString exoPort}") links;
in
{
  inherit
    thunderboltLinks
    thunderboltHosts
    exoPort
    linksForHost
    exoPeersFor
    ;

  user = {
    name = "casazza";
    fullName = "Olive Casazza";
    email = "olive.casazza@schrodinger.com";
  };

  isDeterminate = true;
}
