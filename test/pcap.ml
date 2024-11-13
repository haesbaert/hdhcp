(*
 * Copyright (c) 2012 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2015 Christiano F. Haesbaert <haesbaert@haesbaert.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

let () = Printexc.record_backtrace true

let printf = Printf.printf

let verbose = (Array.length Sys.argv) = 2 && Sys.argv.(1) = "-v"

(*type pcap_header = {
  magic_number:  uint32_t;  (* magic number *)
  version_major: uint16_t;  (* major version number *)
  version_minor: uint16_t;  (* minor version number *)
  thiszone:      uint32_t;  (* GMT to local correction *)
  sigfigs:       uint32_t;  (* accuracy of timestamps *)
  snaplen:       uint32_t;  (* max length of captured packets, in octets *)
  network:       uint32_t;  (* data link type *)
  } *)

let get_pcap_header_magic_number cs =
  Cstruct.LE.get_uint32 cs 0

let get_pcap_header_version_major cs =
  Cstruct.LE.get_uint16 cs 4

let get_pcap_header_version_minor cs =
  Cstruct.LE.get_uint16 cs 6

let get_pcap_header_thiszone cs =
  Cstruct.LE.get_uint32 cs 8

let get_pcap_header_sigfigs cs =
  Cstruct.LE.get_uint32 cs 12

let get_pcap_header_snaplen cs =
  Cstruct.LE.get_uint32 cs 16

let get_pcap_header_network cs =
  Cstruct.LE.get_uint32 cs 20

let sizeof_pcap_header = 24

(* type pcap_packet = {
  ts_sec:  uint32_t;  (* timestamp seconds *)
  ts_usec:  uint32_t; (* timestamp microseconds *)
  incl_len: uint32_t; (* number of octets of packet saved in file *)
  orig_len: uint32_t; (* actual length of packet *)
   } *)

let get_pcap_packet_ts_sec cs =
  Cstruct.LE.get_uint32 cs 0

let get_pcap_packet_ts_usec cs =
  Cstruct.LE.get_uint32 cs 4

let get_pcap_packet_incl_len cs =
  Cstruct.LE.get_uint32 cs 8

let get_pcap_packet_orig_len cs =
  Cstruct.LE.get_uint32 cs 12

let sizeof_pcap_packet = 16

let test_packet p len =
  match (Dhcp_wire.pkt_of_buf p len) with
  | Error e -> failwith e
  | Ok pkt ->
    if verbose then
      Format.printf "DHCP: %a\n%!" Dhcp_wire.pp_pkt pkt;
    let buf = Dhcp_wire.buf_of_pkt pkt in
    match (Dhcp_wire.pkt_of_buf buf len) with
    | Error e -> failwith e
    | Ok pkt2 ->
      if pkt2 <> pkt then begin
        printf "buffers differ !\n";
        printf "pcap buf:";
        Cstruct.hexdump p;
        printf "our buf:";
        Cstruct.hexdump buf;
        Format.printf "generated pkt:\n%a\n" Dhcp_wire.pp_pkt pkt2;
        failwith "Serialization bug found !"
  end

let test_pcap_packet (hdr, pkt) =
  let ts_sec = get_pcap_packet_ts_sec hdr in
  let ts_usec = get_pcap_packet_ts_usec hdr in
  let incl_len = get_pcap_packet_incl_len hdr in
  let orig_len = get_pcap_packet_orig_len hdr in
  if verbose then
    printf "***** %lu.%lu  bytes %lu (of %lu)\n%!"
      ts_sec ts_usec incl_len orig_len;
  test_packet pkt (Int32.to_int incl_len)

let test_pcap_header buf =
  let magic = get_pcap_header_magic_number buf in
  let endian =
    match magic with
    |0xa1b2c3d4l -> "bigendian"
    |0xd4c3b2a1l -> "littlendian"
    |_ -> "not a pcap file"
  in
  let version_major = get_pcap_header_version_major buf in
  let version_minor = get_pcap_header_version_minor buf in
  let thiszone = get_pcap_header_thiszone buf in
  let sigfis = get_pcap_header_sigfigs buf in
  let snaplen = get_pcap_header_snaplen buf in
  let header_network = get_pcap_header_network buf in
  if verbose then begin
    printf "pcap_header (len %d)\n%!" sizeof_pcap_header;
    printf "magic_number %lx (%s)\n%!" magic endian;
    printf "version %d %d\n%!" version_major version_minor;
    printf "timezone shift %lu\n%!" thiszone;
    printf "timestamp accuracy %lu\n%!" sigfis;
    printf "snaplen %lu\n%!" snaplen;
    printf "lltype %lx\n%!" header_network
  end

let parse file =
  if verbose then
    printf "parsing %s\n%!" file;
  let fd = Unix.(openfile file [O_RDONLY] 0) in
  let t = Unix_cstruct.of_fd fd in
  if verbose then
    printf "total pcap file length %d\n%!" (Cstruct.length t);

  let header, body = Cstruct.split t sizeof_pcap_header in
  if verbose then
      test_pcap_header header;

  let packets = Cstruct.iter
      (fun buf -> Some (sizeof_pcap_packet + Int32.to_int (get_pcap_packet_incl_len buf)))
      (fun buf -> buf, Cstruct.shift buf sizeof_pcap_packet)
      body
  in
  let num_packets = Cstruct.fold
      (fun a packet -> test_pcap_packet packet; (a+1))
      packets 0
  in
  Unix.close fd;
  if verbose then
    printf "%s had %d packets\n\n%!" file num_packets

let testfiles = ["dhcp.pcap"; "dhcp2.pcap" ]

let t_pcap () =
  List.iter parse testfiles
