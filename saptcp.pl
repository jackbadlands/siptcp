#!/usr/bin/perl

use strict;
use Socket;
use IO::Select;
use IO::Socket;

#my $localaddr="localhost";
#my $localport=5040;


my $conf_localaddr = "127.0.0.2";
my $conf_localport = 0;
my $conf_mode = "l";
my $conf_tcpaddr = "0.0.0.0";
my $conf_tcpport = 5040;

if ( $#ARGV != 4 ) {
    print STDERR "Usage: saptcp udp_host udp_port tcp_mode tcp_host tcp_port\n";
    print STDERR "Examples:\n";
    print STDERR "   Listen: saptcp 0.0.0.0 0 l 0.0.0.0 5055\n";
    print STDERR "   Connect: saptcp 127.0.0.1 5060 c 1.2.3.4 5055\n";
    exit 1;
} else {
    $conf_localaddr = $ARGV[0];
    $conf_localport = $ARGV[1];
    $conf_mode = $ARGV[2];
    $conf_tcpaddr = $ARGV[3];
    $conf_tcpport =$ARGV[4];
}

my $sock = IO::Socket::INET->new(
    Proto    => 'udp',
    LocalPort => 0,
    #LocalAddr => 'localhost',
    #PeerAddr => 'localhost',
    #PeerPort => 5041,
) or die "Could not create socket: $!\n";
$sock->bind($conf_localport, INADDR_ANY);
        
my $sockport = $sock->sockport;
my $sockaddr = $conf_localaddr;

our $sv;

if ($conf_mode eq "l") {
    $sv = IO::Socket::INET->new(
        Proto    => 'tcp',
        LocalPort => $conf_tcpport,
        LocalAddr => $conf_tcpaddr,
        Listen => 1,
        Reuse => 1,
    ) or die "Could not create socket: $!\n";
}

our $cl;

sub obtain_cl() {
    if ($conf_mode eq "l") { 
        $cl = $sv->accept();
    } else {
        $cl = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerPort => $conf_tcpport,
            PeerAddr => $conf_tcpaddr,
        ) or die "Could not create socket: $!\n";
    }
}

obtain_cl();

our $sel = IO::Select->new();

$sel->add($cl);
$sel->add($sock);
$sel->add($sv);

my $buf = "";

my %portmaps_f = ();
my %portmaps_b = ();
my %sockets = ();
my %socket2port = ();
my %received_counter = ();

sub get_portmap($) {
    my $original_port = shift;
    
    unless (exists $portmaps_f{$original_port}) {
        my $s = IO::Socket::INET->new(
            Proto    => 'udp',
            Reuse => 1,
        );
        $s->bind(0, INADDR_ANY);
        my $new_port = $s->sockport;
        print STDERR "New mapping: $original_port->$new_port\n";
        $portmaps_f{$original_port} = $new_port;
        $portmaps_b{$new_port} = $original_port;
        $sockets{$new_port} = $s;
        $socket2port{$s} = $new_port;
        $received_counter{$new_port} = 0;
        $sel->add($s);
        
    }
    
    return $portmaps_f{$original_port};
}

while(my @ready = $sel->can_read) {
    foreach my $fh (@ready) {
        if($conf_mode eq "l" and $fh == $sv) {
            $sel->remove($fh);
            obtain_cl();
            $sel->add($cl);
        }
        elsif($fh == $cl) {
            $cl->recv($buf, 20);
            
            unless ($buf) {
                $sel->remove($fh);
                obtain_cl();
                $sel->add($cl);
                next;
            }
            
            my $cmd = substr($buf,0,1);
            if ($cmd eq "P" or $cmd eq "p") {
                my $srcport = hex(substr($buf, 1, 4));
                my $destaddr = pack("H*", substr($buf,5,8));
                my $destport = hex(substr($buf, 13, 4));
                my $length = hex(substr($buf,17,3));
                my $servadr = sockaddr_in($destport, $destaddr);
                
                $cl->recv($buf, $length);
                
                if ($cmd eq "P" ) {
                 my $req;
                 $buf =~ /^(.*)/;   $req=$1;
                 printf STDERR "%s:%s %s\n", inet_ntoa($destaddr), $destport, $req;
                
                 $buf =~ s/Contact:.*?\r\n//s;
                 $buf =~ s/\r\n\r\n/"\r\nContact: <sip:$sockaddr:$sockport>\r\n\r\n"/se;
                 
                 $buf =~ s/IN IP4 [\d\.]+/"IN IP4 $sockaddr"/eg;
                 
                 $buf =~ s/(m=[a-z]+ +)(\d+)/$1 . get_portmap($2)/ge;
                 $buf =~ s/a=rtcp:(\d+)/"a=rtcp:" . get_portmap($1)/ge;
                 $buf =~ s/(a=candidate:.*?UDP +\d+ +)(\d+(?:\.\d){3}) +(\d+)/
                                      $1.$sockaddr." ".get_portmap($3)   /ge;
                 $sock->send($buf, MSG_DONTWAIT, $servadr);
                } else {
                  my $myport = get_portmap($srcport);
                  $sock->send($sockets{$myport}, MSG_DONTWAIT, $servadr);
                }
            }
        }
        elsif($fh == $sock) {
            my $peername = $sock->recv($buf, 4096, MSG_DONTWAIT);
            if ($peername) {
                my ($peerport, $peeraddr) = sockaddr_in($peername);
                
                $cl->send(sprintf("P%04x%s%04x%03x%s", $sockport, unpack ("H*",$peeraddr), $peerport, length($buf), $buf));
            }
        }
        else {
            my $port = $socket2port{$fh};
            my $mappedport = $portmaps_b{$port};
            my $peername = $fh->recv($buf, 4096, MSG_DONTWAIT);
            
            if ($peername) {
                my ($peerport, $peeraddr) = sockaddr_in($peername);
                
                ++$received_counter{$port};
                
                if($received_counter{$port} == 1) {
                    print STDERR "Mapping $mappedport->$port actually used by ".inet_ntoa($peeraddr).":$peerport\n";
                }
                
                $cl->send(sprintf("p%04x%s%04x%03x%s", 
                    $mappedport, unpack ("H*",$peeraddr), $peerport, length($buf), $buf));
            }
        }
    }
}

=cut
INVITE sip:127.0.0.1 SIP/2.0
Via: SIP/2.0/UDP 127.0.0.1:5002;rport;branch=z9hG4bK+04f2c5b8c7d3fe29ca9c4e527e45ec221+s155+1
From: <sip:127.0.0.1>;tag=s155+1+41c80009+2ee0e11
To: <sip:127.0.0.1>
Call-ID: QOlc3YjnHa9bR4NPm9Ln2Ik7Y8N0u6IV-S
Supported: replaces
Supported: timer
Supported: norefersub, 100rel, timer
Max-Forwards: 70
Contact: <sip:127.0.0.1:5001;ob>
CSeq: 21823 INVITE
Allow: PRACK, INVITE, ACK, BYE, CANCEL, UPDATE, SUBSCRIBE, NOTIFY, REFER, MESSAGE, OPTIONS
Content-Type: application/sdp
Content-Length: 519

v=0
o=- 3563829016 3563829016 IN IP4 127.0.0.1
s=pjmedia
c=IN IP4 127.0.0.1
t=0 0
m=audio 5003 RTP/AVP 96 3 0 8 101
c=IN IP4 127.0.0.1
a=rtcp:5006 IN IP4 127.0.0.1
a=sendrecv
a=rtpmap:96 SILK/8000
a=fmtp:96 useinbandfec=0
a=rtpmap:3 GSM/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:8 PCMA/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ice-ufrag:305f790f
a=ice-pwd:475a4751
a=candidate:H2e3826cd 1 UDP 2130706431 127.0.0.1 5004 typ host
a=candidate:H2e3826cd 2 UDP 2130706430 127.0.0.1 5005 typ host
=cut



=cut
BYE sip:127.0.0.1:5001;ob SIP/2.0
Via: SIP/2.0/UDP 192.168.99.2:5059;rport;branch=z9hG4bK1188417289
From: <sip:127.0.0.1>;tag=1499968249
To: <sip:127.0.0.1>;tag=s155+1+41c80009+2ee0e11
Call-ID: QOlc3YjnHa9bR4NPm9Ln2Ik7Y8N0u6IV-S
CSeq: 2 BYE
Contact: <sip:192.168.99.2:5059>
Max-Forwards: 70
User-Agent: Linphone/3.5.2 (eXosip2/3.6.0)
Content-Length: 0
=cut
