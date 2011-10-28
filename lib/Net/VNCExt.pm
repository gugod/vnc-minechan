package Net::VNCExt;

package Net::VNC;
use strict;

sub send_pointer_event {
    my ($self, $button_mask, $x, $y) = @_;

    $self->socket->print(
        pack(
            'CCnn',
            5,              # message type
            $button_mask,   # button-mask
            $x,             # x-position
            $y,             # y-position
        )
    );
}

sub _send_update_request {
    my ($self, $x, $y, $w, $h) = @_;

    # frame buffer update request
    my $socket = $self->socket;
    my $incremental = $self->_framebuffer ? 1 : 0;

    # $incremental = 0;

    $socket->print(
        pack(
            'CCnnnn',
            3,                  # message_type
            $incremental,       # incremental
            $x || 0,
            $y || 0,
            $w || $self->width,
            $h || $self->height,
        )
    );
}

# sub _receive_message {
#     my $self = shift;

#     my $socket = $self->socket;
#     $socket->read( my $message_type, 1 ) || die 'unexpected end of data';
#     $message_type = unpack( 'C', $message_type );

#     # warn $message_type;

#  # This result is unused.  It's meaning is different for the different methods
#     my $result
#         = !defined $message_type ? die 'bad message type received'
#         : $message_type == 0     ? $self->_receive_update()
#         : $message_type == 1     ? $self->_receive_colour_map()
#         : $message_type == 2     ? $self->_receive_bell()
#         : $message_type == 3     ? $self->_receive_cut_text()
#         : undef; #                         die 'unsupported message type received';

#     return $message_type;
# }

# sub _update_cursor_region {
#     my $self = shift;
#     my $cursordata = $self->_cursordata;
#     if ( !$cursordata ) {
#         $self->_cursordata( $cursordata = {} );
#     }
#     my $x = $cursordata->{x};
#     my $y = $cursordata->{y};

#     $self->_send_update_request($x - 25, $y - 25, 50, 50);
#     while ( ( my $message_type = $self->_receive_message() ) != 0 ) {
#            warn $message_type;
#     }
# }

sub mouse_move_to {
    my ($self, $x, $y) = @_;
    $self->send_pointer_event(0, $x, $y);

    my $cursordata = $self->_cursordata;
    if ( !$cursordata ) {
        $self->_cursordata( $cursordata = {} );
    }
    $cursordata->{x} = $x;
    $cursordata->{y} = $y;
}

sub mouse_click {
    my ($self) = @_;

    my $cursordata = $self->_cursordata;
    if ( !$cursordata ) {
        $self->_cursordata( $cursordata = { x => 0, y => 0 } );
    }

    $self->send_pointer_event(1, $cursordata->{x}, $cursordata->{y});
    $self->send_pointer_event(0, $cursordata->{x}, $cursordata->{y});
}

sub mouse_right_click {
    my ($self) = @_;

    my $cursordata = $self->_cursordata;
    if ( !$cursordata ) {
        $self->_cursordata( $cursordata = { x => 0, y => 0 } );
    }

    $self->send_pointer_event(4, $cursordata->{x}, $cursordata->{y});
    $self->send_pointer_event(0, $cursordata->{x}, $cursordata->{y});
}

1;
