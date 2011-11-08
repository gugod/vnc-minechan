#!/Users/gugod/perl5/perlbrew/perls/perl-5.14.1/bin/perl

use v5.14;

package main;
use AnyEvent;
use Net::VNC;

die "Usage: vnc.pl <vnc-host:port> <password>\n" unless @ARGV;

my $vncopt = {};

{
    my ($host, $password) = @ARGV;
    my ($hostname, $port) = split ":", $host;
    $port ||= 5900;

    $vncopt = {
        hostname => $hostname,
        port     => $port
    };

    $vncopt->{password} = $password if $password;
}

my $vnc = Net::VNC->new($vncopt);
$vnc->depth(24);
$vnc->login();

$vnc->capture;

my $x = AnyEvent->idle(
    cb => sub {
        # $vnc->_send_update_request;
        $vnc->_receive_message();
    }
);

my $w = AnyEvent->timer(
    after => 1,
    interval => 5,
    cb => sub {
        # $vnc->_send_update_request;
        $vnc->_framebuffer->clone->save("/tmp/vnc/" . time . ".png");
    }
);

AnyEvent->condvar->recv;
