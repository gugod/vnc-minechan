package Acme::Minechan;

use strict;
use warnings;
use Carp qw(confess);

use Win32::GuiTest;
use Image::Match;

our $VERSION = 0.1;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	Image::Match->mode("screen");
	return $self;
}

sub debug {
	my ($self) = @_;
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			printf "%  d ", $self->{z}->[$x][$y];
		}
		print "\n";
	}
	print "\n";
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			printf "%.2f ", $self->{p}->[$x][$y];
		}
		print "\n";
	}

}

sub SpawnMinesweeper {
	system("start winmine.exe");
	sleep(1);
}

my $Ms = "^(Minesweeper"
       . "|\x83\x7d\x83C\x83\x93\x83X\x83C\x81\\[\x83p" # CP932(ja)
       . ")";

sub FindWindow {
	my $self = shift;
	my @id = Win32::GuiTest::FindWindowLike(undef, $Ms, "", undef, 1);
	if (@id == 0) {
		SpawnMinesweeper();
		@id = Win32::GuiTest::FindWindowLike(undef, $Ms, $Ms, undef, 1);
		confess "Win32::GuiTest::FindWindowLike failed: $Ms" unless (@id);
	}
	$self->{window_id} = $id[0];
}

sub GetWindowInfo {
	my $self = shift;
	my $id = $self->{window_id};
	$self->{window_text} = Win32::GuiTest::GetWindowText($id);
	$self->{window_class} = Win32::GuiTest::GetClassName($id);
	confess if ($self->{window_class} eq "CabinetWClass"); # Explorer
	my ($x1, $y1, $x2, $y2) = Win32::GuiTest::GetWindowRect($id);
	$self->{window_left}   = $x1;
	$self->{window_right}  = $x2;
	$self->{window_top}    = $y1;
	$self->{window_bottom} = $y2;
	$self->{window_width}  = $x2 - $x1;
	$self->{window_height} = $y2 - $y1;
}

sub ScreenShot {
	my $self = shift;
	my $id = $self->{window_id};
	Win32::GuiTest::SetForegroundWindow($id);
	my $all = Image::Match->screenshot;
	# $all->save("0.png");
	my $win = $all->extract(
		$self->{window_left},  $all->height - $self->{window_bottom},
		$self->{window_width}, $self->{window_height}
	);
	# $win->save("1.png");
	$self->{window_image} = $win;
	$self->CheckEscape;
}

sub ImageLoad {
	my $self = shift;
	my $file = shift;
	if (exists $self->{"img/$file"}) {
		return $self->{"img/$file"};
	} else {
		my $img = Prima::Image->load("$self->{os}/$file.png")
			or confess "Can't load '$file': $@";
		return $img;
	}
}

sub CheckEscape {
	my $self = shift;
	confess "pressed ESC key" if (Win32::GuiTest::IsKeyPressed("ESC"))
}

sub CheckOSimage {
	my $self = shift;
	my ($file) = @_;
	foreach my $dir (glob("img/*")) {
		my $img = Prima::Image->load("$dir/$file")
			or confess "Can't load '$dir/$file': $@";
		$self->{os} = $dir if ($self->{window_image}->match($img));
	}
}

sub CheckOS {
	my $self = shift;
	my @detect = ("LED0.png", "congratulations.png", "END");
	foreach my $file (@detect) {
		if ($file eq "END" ) {
			confess "Failed CheckOS: @detect";
		}
		if (!$self->{os}) {
			$self->CheckOSimage($file);
			last;
		}
	}
}

sub GetLED {
	my $self = shift;
	my $win = $self->{window_image};
	my @LED = ();
	my $count = 0;
	for (my $n = 0; $n <= 9; $n++) {
		my $img = $self->ImageLoad("LED$n");
		my @xy = $win->match($img, multiple => 1);
		$count += scalar @xy;
		for (my $i = 0; $i < @xy; $i += 2) {
			my $x = $xy[$i + 0];
			my $y = $xy[$i + 1]; 
			$LED[$self->{LED_BOX}->{"($x,$y)"}] = $n;
		}
	}
	if ($count == 6 * 2) {
		$self->{bombs_number} = int($LED[0].$LED[1].$LED[2]);
		$self->{time_counter} = int($LED[3].$LED[4].$LED[5]);
	} else {
		warn "LED count is funny: $count";
	}
	return $count;
}

sub GetLED_BOX {
	my $self = shift;
	$self->{LED_BOX} = {};
	my %x = ();
	my %y = ();
	for (my $n = 0; $n <= 9; $n++) {
		my $img = $self->ImageLoad("LED$n");
		my @xy = $self->{window_image}->match($img, multiple => 1);
		for (my $i = 0; $i < @xy; $i += 2) {
			my $x = $xy[$i + 0]; $x{$x}++;
			my $y = $xy[$i + 1]; $y{$y}++;
		}
	}
	my @x = sort {$a <=> $b} keys %x;
	my @y = sort {$a <=> $b} keys %y;
	for (my $k = 0; $k < @y; $k++) {
		for (my $j = 0; $j < @x; $j++) {
			$self->{LED_BOX}->{"($x[$j],$y[$k])"} = $j;
		}
	}
}

sub msleep {
	select(undef, undef, undef, $_[0] / 1000);
}

sub MouseClick {
	my $self = shift;
	my ($x, $y, $mouse) = @_;
	my $xxx = $self->{Xdot}->[$x] + $self->{window_left};
	my $yyy = $self->{Ydot}->[$y] + $self->{window_top};
	Win32::GuiTest::MouseMoveAbsPix($xxx + 6, $yyy + 6);
	Win32::GuiTest::SendMouse($mouse);
	$self->CheckEscape;
}

sub MouseClickPixel {
	my $self = shift;
	my ($x, $y, $mouse) = @_;
	my $xxx = $x + $self->{window_left};
	my $yyy = $y + $self->{window_top};
	Win32::GuiTest::MouseMoveAbsPix($xxx, $yyy);
	Win32::GuiTest::SendMouse($mouse);
	$self->CheckEscape;
}

sub Congratulations {
	my $self = shift;
	my ($xxx, $yyy, $mouse) = @_;
	$self->MouseClickPixel($xxx, $yyy, $mouse);
	msleep(250);
	Win32::GuiTest::SendKeys("{RIGHT}" . ("{BS}" x 20));
	Win32::GuiTest::SendKeys("Perl Mongers ");
	msleep(750);
	Win32::GuiTest::SendKeys("{ENTER}");
	msleep(850);
	Win32::GuiTest::SendKeys("{ENTER}");
	msleep(500);
	Win32::GuiTest::SendKeys("{ENTER}");
	msleep(100);
	exit();
}

sub GetSmile {
	my $self = shift;
	my $win = $self->{window_image};
	my $clear = 0;
	my @xy;
	@xy = $win->match($self->ImageLoad("smile_over"));
	if (@xy) {
		$self->MouseClickPixel($xy[0] + 12, $xy[1] + 12, "{LEFTCLICK}");
		msleep(50);
		$self->ScreenShot;
		return 0;
	}
	@xy = $win->match($self->ImageLoad("congratulations"));
	if (@xy) {
		# High Score
		$self->Congratulations($xy[0], $xy[1], "{LEFTCLICK}");
		return 1;
	}
	@xy = $win->match($self->ImageLoad("smile_clear"));
	if (@xy) {
		msleep(1000);
		$self->MouseClickPixel($xy[0] + 12, $xy[1] + 12, "{LEFTCLICK}");
		msleep(50);
		$self->ScreenShot;
		# High Score
		my $r = $self->GetLED;
		if ($r == 0 || $self->{time_counter} > 0) {
			$self->Congratulations($xy[0] + 12, $xy[1] + 12, "{LEFTCLICK}");
			return 1;
		}
		return 1;
	}
}

sub GetBlock_BOX {
	my $self = shift;
	my %x = ();
	my %y = ();
	for (my $n = -5; $n <= 8; $n++) {
		my $img = $self->ImageLoad("z$n");
		my @xy = $self->{window_image}->match($img, multiple => 1);
		for (my $i = 0; $i < @xy; $i += 2) {
			my $x = $xy[$i + 0]; $x{$x}++;
			my $y = $xy[$i + 1]; $y{$y}++;
		}
	}
	my %BlockX = ();
	my %BlockY = ();
	my @x = sort {$a <=> $b} keys %x;
	my @y = sort {$a <=> $b} keys %y;
	for (my $k = 0; $k < @y; $k++) {
		for (my $j = 0; $j < @x; $j++) {
			$BlockX{"($x[$j],$y[$k])"} = $j + 1;
			$BlockY{"($x[$j],$y[$k])"} = $k + 1;
		}
	}
	$self->{BlockX} = \%BlockX;
	$self->{BlockY} = \%BlockY;
	$self->{X} = scalar @x;
	$self->{Y} = scalar @y;
	$self->{Xdot} = [0, @x];
	$self->{Ydot} = [0, @y];
}

sub GetBlock {
	my $self = shift;
	my $z = [];
	my $p = [];
	for (my $n = -6; $n <= 8; $n++) {
		my $img = $self->ImageLoad("z$n");
		my @xy = $self->{window_image}->match($img, multiple => 1);
		for (my $i = 0; $i < @xy; $i += 2) {
			my $xx = $xy[$i + 0];
			my $yy = $xy[$i + 1];
			my $x  = $self->{BlockX}->{"($xx,$yy)"};
			my $y  = $self->{BlockY}->{"($xx,$yy)"};
			if (!defined $x) {
				$self->debug;
				confess "($xx, $yy) = z$n.png ";
			}
			$z->[$x][$y] = $n;
		}
	}
	my $remain = 0;
	for (my $y = 0; $y <= $self->{Y} + 1; $y++) {
		for (my $x = 0; $x <= $self->{X} + 1; $x++) {
			if($x == 0 || $x == $self->{X} + 1 || $y == 0 || $y == $self->{Y} + 1) {
				$z->[$x][$y] = -2;
				$p->[$x][$y] = 0.0;
			} else {
				if (!defined $z->[$x][$y]) {
					warn "z->[$x][$y]: not defined";
					return -1;
				}
				if ($z->[$x][$y] == -1) {
					$remain++;
				}
			}
		}
	}
	$self->{z} = $z;
	$self->{p} = $p;
	$self->{remain} = $remain;
	return 0;
}

sub around {
	my ($self, $p, $z, $x, $y, $f, @args) = @_;
	my $sum = 0;
	for (my $d = -1; $d <= 1; $d++) {
		$sum += $f->($p, $z, $x + $d, $y - 1, @args);
		$sum += $f->($p, $z, $x + $d, $y + 0, @args) if ($d);
		$sum += $f->($p, $z, $x + $d, $y + 1, @args);
	}
	return $sum;
}

sub CalcProbability {
	my $self = shift;
	my $p = $self->{p};
	my $z = $self->{z};
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			if (!defined $z->[$x][$y]) {
				confess "undefined value: \$z->[$x][$y]";
			}
			if ($z->[$x][$y] == -1) {
				$p->[$x][$y] = 1.0 / $self->{remain};
			} elsif ($z->[$x][$y] == -5) {
				$p->[$x][$y] = 0.0;
			} else {
				$p->[$x][$y] = 0.0;
			}
		}
	}
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			if ($z->[$x][$y] > 0) {
				my $r = $self->around($p, $z, $x, $y, sub {
					my ($p, $z, $x, $y) = @_;
					return ($z->[$x][$y] == -1 || $z->[$x][$y] == -5) ? 1 : 0;
				});
				my $b = $self->around($p, $z, $x, $y, sub {
					my ($p, $z, $x, $y) = @_;
					return ($z->[$x][$y] == -5) ? 1 : 0;
				});
				my $n = $r - $b;
				if ($n > 0 && $z->[$x][$y] > $b) {
					$self->around($p, $z, $x, $y, sub {
						my ($p, $z, $x, $y, $n) = @_;
						my $pp = 1.0 / $n;
						if ($pp > $p->[$x][$y] && $z->[$x][$y] == -1) {
							$p->[$x][$y] = $pp;
						}
					}, $n);
				}
				if ($n > 0 && $z->[$x][$y] == $r) {
					$self->around($p, $z, $x, $y, sub {
						my ($p, $z, $x, $y, $n) = @_;
						my $pp = 2.0; # 1.0
						if ($pp > $p->[$x][$y] && $z->[$x][$y] == -1) {
							$p->[$x][$y] = $pp;
						}
					}, $n);
				}
			}
		}
	}
	$self->{p} = $p;
}

sub Click0 {
	my $self = shift;
	my $z = $self->{z};
	my $click = 0;
	return 0 if ($self->{bombs_number} > 0);
	confess if (!defined $self->{bombs_number});
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			if ($z->[$x][$y] == -1) {
				$self->MouseClick($x, $y, "{LEFTCLICK}");
				$z->[$x][$y] = 0;
				$click++;
			}
		}
	}
	return $click;
}


sub Click1 {
	my $self = shift;
	my $click = 0;
	my $z = $self->{z};
	my $p = $self->{p};
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			if ($p->[$x][$y] == 1.0 || $p->[$x][$y] == 2.0) {
				$self->MouseClick($x, $y, "{RIGHTCLICK}");
				$z->[$x][$y] = -5;
				$click++;
			}
		}
	}
	return $click;
}

sub Click2 {
	my $self = shift;
	my $z = $self->{z};
	my $p = $self->{p};
	my $click = 0;
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			if (!defined $z->[$x][$y]) { confess }
			if ($z->[$x][$y] == -5) {
				$self->around($p, $z, $x, $y, sub {
					my ($p, $z, $x, $y) = @_;
					return 0 if ($z->[$x][$y] == -2);
					my $not_open = $self->around($p, $z, $x, $y, sub {
						my ($p, $z, $x, $y) = @_;
						return ($z->[$x][$y] == -1) ? 1 : 0;
					});
					return 0 if ($not_open == 0);
					my $b = $self->around($p, $z, $x, $y, sub {
						my ($p, $z, $x, $y) = @_;
						return ($z->[$x][$y] == -5) ? 1 : 0;
					});
					if ($z->[$x][$y] == $b) {
						$self->MouseClick($x, $y, "{LEFTDOWN}{RIGHTDOWN}{LEFTUP}{RIGHTUP}");
						$p->[$x][$y] = 9.99;
						$click++;
					}
				});
			}
		}
	}
	return $click;
}

sub Click3 {
	my $self = shift;
	my $min_p = 1.0;
	my %count;
	my $rand_x;
	my $rand_y;
	for (my $y = 1; $y <= $self->{Y}; $y++) {
		for (my $x = 1; $x <= $self->{X}; $x++) {
			my $pp = $self->{p}->[$x][$y];
			if ($min_p > $pp && $pp > 0.0) {
				$min_p = $pp;
			}
			my $i = $count{$pp}++;
			$rand_x->{$pp}->[$i] = $x;
			$rand_y->{$pp}->[$i] = $y;
		}
	}
	if ($count{$min_p} > 0) {
		my $pp = $min_p;
		my $i = int(rand($count{$min_p}));
		my $x = $rand_x->{$pp}->[$i];
		my $y = $rand_y->{$pp}->[$i];
		my $xxx = $self->{Xdot}->[$x] + $self->{window_left};
		my $yyy = $self->{Ydot}->[$y] + $self->{window_top};
		Win32::GuiTest::MouseMoveAbsPix($xxx + 6, $yyy + 6);
		Win32::GuiTest::SendMouse("{LEFTCLICK}");
		return 1;
	} else {
		return 0;
	}
}

sub main {
	my $self = new __PACKAGE__;
	$self->FindWindow;
	$self->GetWindowInfo;
	$self->ScreenShot;
	$self->CheckOS;
	$self->GetLED_BOX;
	$self->GetBlock_BOX;
	for (1..9999) {
		$self->ScreenShot;
		$self->GetSmile;
		$self->GetLED;
		for (1..3) {
			my $failed = $self->GetBlock;
			if ($failed) {
				msleep(200); # retry
				$self->ScreenShot;
			} else {
				last;
			}
		}
		$self->CalcProbability;
		my $c0 = $self->Click0;
		if ($c0 == 0) {
			my $c1 = $self->Click1;
			my $c2 = $self->Click2;
			if ($c1 + $c2 == 0) {
				my $c3 = $self->Click3;
			}
		}
		$self->debug;
	}
}

main();

1;
