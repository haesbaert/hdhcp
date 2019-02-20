open Lwt.Infix
open Mirage_protocols_lwt

module Make(Dhcp_client : DHCP_CLIENT) (R : Mirage_random.C) (C : Mirage_clock.MCLOCK) (E : ETHERNET) (Arp : ARP) = struct
  (* for now, just wrap a static ipv4 *)
  include Static_ipv4.Make(R)(C)(E)(Arp)
  let connect dhcp clock ethernet arp =
    Lwt_stream.last_new dhcp >>= fun (config : ipv4_config) ->
    connect ~ip:config.address ~network:config.network ~gateway:config.gateway clock ethernet arp
end
