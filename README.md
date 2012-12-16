A simple hacky [SIP](http://en.wikipedia.org/wiki/Session_Initiation_Protocol) [ALG](http://en.wikipedia.org/wiki/Application-level_gateway) that wraps SIP UDP connection (both control and media sessions) in a single TCP connection (to be tunneled through SSH, for example).

My usecase:

* On VPS run:

        siptcp.pl l 0.0.0.0 4555 93.174.88.117 0.0.0.0 5060 127.0.0.1 5060
        
    it means "Listen TCP port 4555; also listen UDP port 5060 and forward packets to 127.0.0.1:5060 in peer's network".  
    93.174.88.117 is my VPS's IP address.
    
* Locally I run:

        siptcp.pl c 93.174.88.117 4555 127.0.0.1 127.0.0.1 5060 86.64.162.35 5060
        
    it means "Connect  to TCP 93.174.88.117:4555, 127.0.0.1 is my IP address, listen UDP 127.0.0.1:5060 and redirect it to peer's 86.64.162.35:5060 (ekiga.net)".
    
It works by searching SIP headers and data for IPv4 address:port occurences and replacing them by local port forwards. It does not comply



Example of SIP request that siptcp receives:

    INVITE sip:vi0oss@127.0.0.10;line=6fe4a000ce83c65 SIP/2.0
    Record-Route: <sip:86.64.162.35;lr=on;did=f5.d98eea76>
    Record-Route: <sip:85.17.186.7;lr;ftag=s70+1+41d30002+1b600e49;did=2c4.46107625>
    Via: SIP/2.0/UDP 86.64.162.35;branch=z9hG4bKdc39.7e556d45.6
    Via: SIP/2.0/UDP 85.17.186.7;branch=z9hG4bKdc39.aea72b24.0
    Via: SIP/2.0/UDP 46.56.13.106:5059;received=46.56.13.106;rport=5059;branch=z9hG4bK+02622c53c1020711d1b58db05197596c1+s70+1
    From: <sip:vi0oss@sip2sip.info>;tag=s70+1+41d30002+1b600e49
    To: <sip:vi0oss@ekiga.net>
    Min-SE: 90
    Session-Expires: 1800
    Call-ID: fxqF1xW3jO9LnRqfaCB-y7xN2eGLTtS.-S
    Supported: replaces
    Supported: timer
    Supported: norefersub, 100rel, timer
    Max-Forwards: 68
    Contact: <sip:vi0oss@46.56.13.106:5059;ob>
    CSeq: 4224 INVITE
    Allow: PRACK, INVITE, ACK, BYE, CANCEL, UPDATE, SUBSCRIBE, NOTIFY, REFER, MESSAGE, OPTIONS
    User-Agent: CSipSimple_X10i-10/r2041
    Content-Type: application/sdp
    Content-Length: 669

    v=0
    o=- 3564621469 3564621469 IN IP4 46.56.13.106
    s=pjmedia
    c=IN IP4 85.17.186.6
    t=0 0
    m=audio 55552 RTP/AVP 96 3 0 8 101
    c=IN IP4 85.17.186.6
    a=rtcp:55553 IN IP4 85.17.186.6
    a=sendrecv
    a=rtpmap:96 SILK/8000
    a=fmtp:96 useinbandfec=0
    a=rtpmap:3 GSM/8000
    a=rtpmap:0 PCMU/8000
    a=rtpmap:8 PCMA/8000
    a=rtpmap:101 telephone-event/8000
    a=fmtp:101 0-15
    a=ice-ufrag:3dbd8afa
    a=ice-pwd:344d7cd4
    a=candidate:R6ba1155 1 UDP 16777215 85.17.186.6 55552 typ relay
    a=candidate:R6ba1155 2 UDP 16777214 85.17.186.6 55553 typ relay
    a=candidate:H2e380d6a 1 UDP 2130706431 46.56.13.106 50075 typ host
    a=candidate:H2e380d6a 2 UDP 2130706430 46.56.13.106 54134 typ host

Here is result of siptcp's patching of the request:

    INVITE sip:vi0oss@127.0.0.10;line=6fe4a000ce83c65 SIP/2.0
    Record-Route: <sip:127.0.0.1:52696;lr=on;did=f5.d98eea76>
    Record-Route: <sip:127.0.0.1:48511;lr;ftag=s70+1+41d30002+1b600e49;did=2c4.46107625>
    Via: SIP/2.0/UDP 127.0.0.1:52696;branch=z9hG4bKdc39.7e556d45.6
    Via: SIP/2.0/UDP 127.0.0.1:48511;branch=z9hG4bKdc39.aea72b24.0
    Via: SIP/2.0/UDP 127.0.0.1:42753;received=127.0.0.1;rport=42753;branch=z9hG4bK+02622c53c1020711d1b58db05197596c1+s70+1
    From: <sip:vi0oss@sip2sip.info>;tag=s70+1+41d30002+1b600e49
    To: <sip:vi0oss@ekiga.net>
    Min-SE: 90
    Session-Expires: 1800
    Call-ID: fxqF1xW3jO9LnRqfaCB-y7xN2eGLTtS.-S
    Supported: replaces
    Supported: timer
    Supported: norefersub, 100rel, timer
    Max-Forwards: 68
    Contact: <sip:vi0oss@127.0.0.1:42753;ob>
    CSeq: 4224 INVITE
    Allow: PRACK, INVITE, ACK, BYE, CANCEL, UPDATE, SUBSCRIBE, NOTIFY, REFER, MESSAGE, OPTIONS
    User-Agent: CSipSimple_X10i-10/r2041
    Content-Type: application/sdp
    Content-Length: 650

    v=0
    o=- 3564621469 3564621469 IN IP4 127.0.0.1
    s=pjmedia
    c=IN IP4 127.0.0.1
    t=0 0
    m=audio 33545 RTP/AVP 96 3 0 8 101
    c=IN IP4 127.0.0.1
    a=rtcp:36077 IN IP4 127.0.0.1
    a=sendrecv
    a=rtpmap:96 SILK/8000
    a=fmtp:96 useinbandfec=0
    a=rtpmap:3 GSM/8000
    a=rtpmap:0 PCMU/8000
    a=rtpmap:8 PCMA/8000
    a=rtpmap:101 telephone-event/8000
    a=fmtp:101 0-15
    a=ice-ufrag:3dbd8afa
    a=ice-pwd:344d7cd4
    a=candidate:R6ba1155 1 UDP 16777215 127.0.0.1 33545 typ relay
    a=candidate:R6ba1155 2 UDP 16777214 127.0.0.1 36077 typ relay
    a=candidate:H2e380d6a 1 UDP 2130706431 127.0.0.1 59466 typ host
    a=candidate:H2e380d6a 2 UDP 2130706430 127.0.0.1 41761 typ host

Just search&replace all IP addresses without thinking much and forward everything though TCP...