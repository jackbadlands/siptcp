#!/usr/bin/perl

use strict;
use Socket;
use IO::Select;
use IO::Socket;

#my $localaddr="localhost";
#my $localport=5040;


my $conf_localaddr;
my $conf_localport;
my $conf_remoteaddr;
my $conf_remoteport;
my $conf_myip;
my $do_open_socket;
my $conf_mode;
my $conf_tcpaddr;
my $conf_tcpport;

if ( $#ARGV != 3 and $#ARGV != 7) {
    print STDERR "Usage: saptcp tcp_mode tcp_host tcp_port ip_address_to_report [udp_local_address ".
                         "udp_local_port udp_remove_address udp_remove_port]\n";
    print STDERR "Examples:\n";
    print STDERR "   Server side: saptcp l 0.0.0.0 5055 1.2.3.4\n";
    print STDERR "   NATted client side: saptcp c 1.2.3.4 5055 127.0.0.1 127.0.0.1 5060 81.23.228.129 5060\n";
    exit 1;
} else {
    $conf_mode = $ARGV[0];
    $conf_tcpaddr = $ARGV[1];
    $conf_tcpport =$ARGV[2];
    $conf_myip =$ARGV[3];
    if ($#ARGV == 7) {
        $do_open_socket = 1;
        $conf_localaddr = $ARGV[4];
        $conf_localport = $ARGV[5];
        $conf_remoteaddr = $ARGV[6];
        $conf_remoteport = $ARGV[7];
    } else {
        $do_open_socket = 0;
    }
}

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
$sel->add($sv) if $conf_mode eq "l";

my $buf = "";

my %sockets = ();
my %socket2port = ();
my %received_counter = ();
my %mapped_hosts = ();
my %mapped_ports = ();
my %hostport2map = ();
my %capital_P_mappings = ();

sub get_portmap($$) {
    my $original_host = shift;
    my $original_port = shift;
    my $hostport = sprintf("%s%04x", unpack ("H*",$original_host), $original_port);
    unless (exists $hostport2map{$hostport}) {
        my $s = IO::Socket::INET->new(
            Proto    => 'udp',
            Reuse => 1,
        );
        $s->bind(0, INADDR_ANY);
        my $new_port = $s->sockport;
        print STDERR "New mapping: ".inet_ntoa($original_host).":$original_port->$new_port\n";
        $mapped_hosts{$new_port} = $original_host;
        $mapped_ports{$new_port} = $original_port;
        $sockets{$new_port} = $s;
        $socket2port{$s} = $new_port;
        $hostport2map{$hostport} = $new_port;
        $received_counter{$new_port} = 0;
        $capital_P_mappings{$new_port} = 0;
        $sel->add($s);
        
    }
    
    return $hostport2map{$hostport};
}


my $sock = undef;
my $sock_port = undef;
my $remoteaddr = undef;
my $remoteport = undef;
if ($do_open_socket) {
    $sock = IO::Socket::INET->new(
        Proto    => 'udp',
        LocalPort => 0,
        #LocalAddr => 'localhost',
        #PeerAddr => 'localhost',
        #PeerPort => 5041,
    ) or die "Could not create socket: $!\n";
    $sock->bind($conf_localport, inet_aton($conf_localaddr));
    $sock_port = $sock->sockport;
    
    $remoteaddr = inet_aton($conf_remoteaddr);
    $remoteport = $conf_remoteport;
    
    $socket2port{$sock} = $conf_localport;
    $mapped_hosts{$conf_localport} = $remoteaddr;
    $mapped_ports{$conf_localport} = $remoteport;
    $capital_P_mappings{$conf_localport} = 1;
    
    $sel->add($sock);
}


while(my @ready = $sel->can_read) {
    foreach my $fh (@ready) {
        if($conf_mode eq "l" and $fh == $sv) {
            $sel->remove($fh);
            obtain_cl();
            $sel->add($cl);
        }
        elsif($fh == $cl) {
            $cl->recv($buf, 28);
            
            unless ($buf) {
                $sel->remove($fh);
                obtain_cl();
                $sel->add($cl);
                next;
            }
            
            my $cmd = substr($buf,0,1);
            if ($cmd eq "P" or $cmd eq "p") {
                my $srcaddr = pack("H*", substr($buf,1,8));
                my $srcport = hex(substr($buf, 9, 4));
                my $destaddr = pack("H*", substr($buf,13,8));
                my $destport = hex(substr($buf, 21, 4));
                my $length = hex(substr($buf,25,3));
                
                my $srchostport = sprintf("%s04x", unpack ("H*",$srcaddr), $srcport);                
                my $localport = get_portmap($srcaddr, $srcport);
                $capital_P_mappings{$localport} = 1;
                my $socket_to_use = $sockets{$localport};
                
                my $destname = sockaddr_in($destport, $destaddr);
                
                $cl->recv($buf, $length);
                
                if ($cmd eq "P" ) {
                 my $req;
                 $buf =~ /^(.*)/;   $req=$1;
                 printf STDERR "O %s:%s->%s:%s %s\n", 
                    inet_ntoa($srcaddr), $srcport, 
                    inet_ntoa($destaddr), $destport, 
                    $req;
                
                 $buf =~ s/Contact:.*?\r\n//s;
                 $buf =~ s/\r\n\r\n/"\r\nContact: <sip:$conf_myip:$localport>\r\n\r\n"/se;
                 
                 $buf =~ s/IN IP4 [\d\.]+/"IN IP4 $conf_myip"/eg;
                 
                 $buf =~ s/(m=[a-z]+ +)(\d+)/$1 . get_portmap($srcaddr, $2)/ge;
                 $buf =~ s/a=rtcp:(\d+)/"a=rtcp:" . get_portmap($srcaddr, $1)/ge;
                 $buf =~ s/(a=candidate:.*?UDP +\d+ +)(\d+(?:\.\d){3}) +(\d+)/
                                      $1.$conf_myip." ".get_portmap($srcaddr, $3)   /ge;
                }
                $socket_to_use->send($buf, MSG_DONTWAIT, $destname);
            }
        }
        elsif($do_open_socket and $fh == $sock) {
            my $peername = $sock->recv($buf, 4096, MSG_DONTWAIT);
            if ($peername) {
                my ($peerport, $peeraddr) = sockaddr_in($peername);
                
                my $req;
                $buf =~ /^(.*)/;   $req=$1;
                printf STDERR "I %s:%s->%s:%s %s\n", 
                    inet_ntoa($peeraddr), $peerport, 
                    inet_ntoa($remoteaddr), $remoteport, 
                    $req;
                
                $cl->send(sprintf("P%s%04x%s%04x%03x%s",
                    unpack ("H*",$peeraddr),   $peerport,
                    unpack ("H*",$remoteaddr), $remoteport, 
                    length($buf), $buf));
            }
        }
        else {
            my $port = $socket2port{$fh};
            my $mappedhost = $mapped_hosts{$port};
            my $mappedport = $mapped_ports{$port};
            my $letter = 'p';
            $letter = 'P' if $capital_P_mappings{$port};
            
            my $peername = $fh->recv($buf, 4096, MSG_DONTWAIT);
            
            if ($peername) {
                my ($peerport, $peeraddr) = sockaddr_in($peername);
                
                ++$received_counter{$port};
                
                if ($letter eq "P") {
                    my $req;
                    $buf =~ /^(.*)/;   $req=$1;
                    printf STDERR "i %s:%s->%s:%s %s\n", 
                        inet_ntoa($peeraddr), $peerport, 
                        inet_ntoa($mappedhost), $mappedport, 
                        $req;
                } else {
                    if($received_counter{$port} == 1) {
                        print STDERR "Mapping ".inet_ntoa($mappedhost).":$mappedport".
                          "->$port actually used by ".inet_ntoa($peeraddr).":$peerport\n";
                    }
                }
                
                $cl->send(sprintf("%s%s%04x%s%04x%03x%s", $letter,
                    unpack ("H*",$peeraddr), $peerport, 
                    unpack ("H*",$mappedhost), $mappedport, 
                    length($buf), $buf));
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
