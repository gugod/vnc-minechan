use v5.14;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";

package VNC::Minechan;
use Mouse;
use Quantum::Superpositions;
use Imager::Search ();
use Imager::Search::Image ();

has vnc => (
    is => 'ro',
    required => 1
);

has app_boundary => (
    is => 'rw',
    default => sub { undef }
);

has board => (
    is => 'rw'
);

has board_position => (
    is => 'rw'
);

has probability => (
    is => 'rw'
);

has game_status => (
    is => 'rw',
    default => sub { "unknown" }
);

has latest_screenshot => (
    is => 'rw'
);

has cached_patterns => (
    is => 'rw',
    default => sub { {} }
);

our $DEBUG = 0;

sub murmur($) {
    if ($DEBUG) {
        say(@_);
    }
}

sub take_screenshot {
    my $self = shift;

    $self->vnc->mouse_move_to(1, 1);

    my $file = "out/screen.png";
    my $capture = $self->vnc->capture();

    if ($self->app_boundary) {
        $capture = $capture->crop(@{ $self->app_boundary });
    }

    $capture->save($file);

    my $screen = Imager::Search::Image->new(
        driver => "Imager::Search::Driver::HTML24",
        file   => $file
    );

    $self->latest_screenshot($screen);

    return $screen;
}

sub mouse_click_at {
    my ($self, $x, $y) = @_;

    $self->mouse_move_to($x, $y);
    $self->vnc->mouse_click;
}

sub mouse_right_click_at {
    my ($self, $x, $y) = @_;

    $self->mouse_move_to($x, $y);
    $self->vnc->mouse_right_click;
}

sub mouse_move_to {
    my ($self, $x, $y) = @_;

    if ($_ = $self->app_boundary) {
        $x += $_->[0];
        $y += $_->[1];
    }

    $self->vnc->mouse_move_to($x, $y);
}

sub find_on_screen {
    my ($self, $stuff, $cb) = @_;

    murmur "    Finding $stuff";

    my $screen = $self->latest_screenshot;

    my $pattern = $self->cached_patterns->{$stuff} ||= Imager::Search::Pattern->new(
        driver => "Imager::Search::Driver::HTML24",
        file   => "${stuff}.png"
    );

    my @matches = $screen->find($pattern);

    if (@matches) {
        murmur "        found at: " . join(" ", map { "(" . $_->center_x . ", " . $_->center_y . ")" } @matches);
        if ($cb) {
            return $cb->(@matches);
        }
    }
    else {
        murmur "        not found";
    }

    return @matches;
}

sub inspect_board {
    my $self = shift;

    $self->take_screenshot;

    $self->game_status("unknown");

    while ($self->game_status eq "unknown") {
        ## Maybe some dialog pops up.
        $self->find_on_screen(
            "img/button-confirm",
            sub {
                $self->vnc->send_key_event_string("VNC::Minechan");

                for my $matched (@_) {
                    $self->mouse_click_at($matched->center_x, $matched->center_y);
                }

                ## Will unable to see button-confirm-large if the screenshot is too small.
                if ($self->app_boundary && $self->app_boundary->[2] < 300) {
                    $self->app_boundary(undef);
                    $self->take_screenshot;
                }

                sleep 1;
            }
        );

        $self->find_on_screen(
            "img/button-confirm-large",
            sub {
                for my $matched (@_) {
                    $self->mouse_click_at($matched->center_x, $matched->center_y);
                }
            }
        );

        murmur "Deciding game status...";

        if ($self->find_on_screen("img/xp/smile_over")) {
            $self->game_status("over");
            return;
        }
        elsif ($self->find_on_screen("img/xp/smile_clear")) {
            $self->game_status("clear");
            return;
        }
        elsif ($self->find_on_screen("img/xp/smile_start")) {
            $self->game_status("start");
            last;
        }

        $self->take_screenshot;
    }

    my @board;

    for my $n (-6..8) {
        $self->find_on_screen(
            "img/xp/z$n", sub {
                for my $matched (@_) {
                    push @board, [$matched->center_y, $matched->center_x, $n];
                }
            }
        );
    }

    @board = sort { $a->[0] <=> $b->[0] } sort { $a->[1] <=> $b->[1] }  @board;
    my $first_cell = [$board[0]->[0], $board[0]->[1]];

    @board = map {
        [ ($_->[0] - $first_cell->[0])/16,  ($_->[1] - $first_cell->[1])/16, $_->[2], $_->[1], $_->[0] ]
    } @board;

    my $board = [];
    my $pos   = [];
    for (@board) {
        if ($_->[0] >= 0 && $_->[0] >= 0) {
            $board->[ $_->[0] ]->[ $_->[1] ] = $_->[2];
            $pos->[   $_->[0] ]->[ $_->[1] ] = [ $_->[3], $_->[4] ];
        }
    }
    $self->board($board);
    $self->board_position($pos);

    ## find app boundary;
    unless ($self->app_boundary) {
        my $cols = @$board;
        my $rows = @{$board->[0]};

        my $x   = $pos->[0][0][0] - 30;
        my $y   = $pos->[0][0][1] - 100;

        $x = 0 if $x < 0;
        $y = 0 if $y < 0;

        my $width  = $pos->[$cols - 1][$rows - 1][0] + 30 - $x;
        my $height = $pos->[$cols - 1][$rows - 1][1] + 30 - $y;

        say "### app boundary: $x $y $width $height";
        $self->app_boundary([$x, $y, $width, $height]);
        $self->take_screenshot;
    }
}

sub dump_board {
    my $self  = shift;
    my $board = $self->board;

    my $last = 0;

    say "## " . $self->game_status;
    $self->board_cells_each(
        sub {
            my ($i, $j) = @_;
            print "\n" if ($i != $last);

            if (defined($board->[$i][$j])) {
                print(sprintf('%2d ', $board->[$i][$j]));
            }
            else {
                print('?? ');
            }

            $last = $i;
        }
    );

    print "\n";
}

sub dump_probability {
    my $self  = shift;
    my $board = $self->probability;

    my $last = 0;

    say "## probability";
    $self->board_cells_each(
        sub {
            my ($i, $j) = @_;
            print "\n" if ($i != $last);

            if (defined($board->[$i][$j])) {
                print(sprintf('%2.2f ', $board->[$i][$j]));
            }
            else {
                print('---- ');
            }

            $last = $i;
        }
    );

    print "\n\n";
}

sub board_cells_each {
    my ($self, $cb) = @_;
    my $board = $self->board;

    for my $i (0..$#$board) {
        for my $j (0..$#{ $board->[$i] }) {
            $cb->($i, $j);
        }
    }
}

sub think {
    my $self = shift;
    my $probability = [];
    my $board = $self->board;

    my $board_cols = 1 + $#$board;
    my $board_rows = 1 + $#{ $board->[0] };

    $self->board_cells_each(
        sub {
            my ($i, $j) = @_;
            $probability->[$i][$j] = undef;
        }
    );

    $self->board_cells_each(
        sub {
            my ($i, $j) = @_;
            return unless defined($board->[$i][$j]) && $board->[$i][$j] >= 1;

            my @around = grep {
                defined($board->[$_->[0]][$_->[1]])
            } grep {
                $_->[0] >= 0 && $_->[1] >= 0 &&
                $_->[0] < $board_cols &&
                $_->[1] < $board_rows
            } (
                [$i-1, $j-1], [$i-1, $j], [$i-1, $j+1],
                [$i,   $j-1],             [$i,   $j+1],
                [$i+1, $j-1], [$i+1, $j], [$i+1, $j+1]
            );

            my @unknowns = grep { any(-1, -6) == $board->[$_->[0]][$_->[1]]     } @around;
            my @mines    = grep { $board->[$_->[0]][$_->[1]] == any(-5, -4, -3) } @around;

            for (@mines) {
                $probability->[$_->[0]][$_->[1]] = 2;
            }

            if (@unknowns > 0) {
                my $p = ($board->[$i][$j] - @mines) / @unknowns;
                # $p = 0 if ($p < 0);

                for (@unknowns) {
                    my $p_xy = $probability->[$_->[0]][$_->[1]];
                    if (defined($p_xy)) {
                        if ($p == any(0, 1)) {
                            $probability->[$_->[0]][$_->[1]] = $p;
                        }
                    }
                    else {
                        $probability->[$_->[0]][$_->[1]] = $p;
                    }
                }
            }
        }
    );

    $self->probability($probability);

    $self->dump_board;
    $self->dump_probability;

    return;
}

sub next_move {
    my $self = shift;
    my $p = $self->probability;
    my $pos = $self->board_position;

    ## Left-click all the cells with p=0
    ## Right-click all the cells with p=1

    my (@zeros, @ones);
    for my $i (0..$#$p) {
        for my $j (0..$#{ $p->[$i] }) {
            if (defined($p->[$i][$j])) {
                if ($p->[$i][$j] == 1) {
                    push @ones, [$i, $j];
                }
                elsif ($p->[$i][$j] == 0) {
                    push @zeros, [$i, $j];
                }
            }
        }
    }

    for (@ones) {
        my ($i, $j) = @$_;
        my ($x, $y) = @{ $pos->[$i][$j] };

        $self->mouse_right_click_at($x, $y);

        murmur "Right-click on ($i, $j)[$x, $y]";
    }

    for (@zeros) {
        my ($i, $j) = @$_;
        my ($x, $y) = @{ $pos->[$i][$j] };

        $self->mouse_click_at($x, $y);

        murmur "Click on ($i, $j)[$x, $y]";
    }

    if (@zeros == 0 && @ones == 0) {
        murmur "Next move: need to guess.";

        my $board = $self->board;
        my @candidates;
        for my $i (0..$#$board) {
            for my $j (0..$#{ $board->[$i] }) {

                my $v = $board->[$i][$j];
                my $p = $self->probability->[$i][$j];
                if (defined($v) && $v == -1) {
                    if (defined( $p ) && $p < 0.3) {
                        push @candidates, [$i, $j]
                    }
                    else {
                        push @candidates, [$i, $j];
                    }
                }
            }
        }

        if (@candidates) {
            my $guess = $candidates[ int(rand(0+@candidates)) ];
            $self->mouse_click_at(@{ $self->board_position->[$guess->[0]][$guess->[1]] });
            murmur "    click on: " . join(",", @$guess);
        }
        else {
            murmur "    no idea how to guess. Restart!";

            $self->reset;
        }
    }
}

sub start {
    my $self = shift;

    while(1) {
        $self->inspect_board;

        if ($self->game_status eq any('over', 'clear')) {
            say "Game " . $self->game_status;
            $self->reset;
        }
        else {
            $self->think;
            $self->next_move;
        }

        sleep 1;
    }
}

sub reset {
    my $self = shift;

    my $restart = sub {
        my @matches = @_;
        my $m = $matches[0];

        $self->mouse_click_at($m->center_x, $m->center_y);
    };

    $self->find_on_screen("img/xp/smile_start", $restart);
    $self->find_on_screen("img/xp/smile_over",  $restart);
    $self->find_on_screen("img/xp/smile_clear", $restart);
}

package main;
use Net::VNC 0.40;
use Net::VNCExt;

die "Usage: vnc-minechan.pl <vnc-host:port> <password>\n" unless @ARGV;

my $vnc;
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

$vnc = Net::VNC->new($vncopt);
$vnc->hide_cursor(1);
$vnc->depth(24);
$vnc->login();
$vnc->capture;

# $vnc->_disable_continuous_updates;

say "Login to " . $vnc->name . ": " . $vnc->width . "x" . $vnc->height;

my $minechan = VNC::Minechan->new(vnc => $vnc);

say "Minechan started. Hit Ctrl-C to quit.";
$minechan->start;
