package Net::VNCExt;

package Net::VNC;
use strict;
use Carp;

sub _disable_continuous_updates {
    my ($self) = @_;

    # http://tigervnc.sourceforge.net/cgi-bin/rfbproto#enablecontinuousupdates
    $self->socket->print(
        pack(
            'CCnnnn',
            150,
            0,
            0,
            0,
            $self->width,
            $self->height
        )
    );

    # Consume the "EndOfContinuousUpdates" message
    $self->socket->read( my $message_type, 1 ) || die 'unexpected end of data';
    $message_type = unpack( 'C', $message_type );
    # assert $message_type == 150;
}

sub _send_update_request {
    my ($self, $x, $y, $w, $h) = @_;
    # frame buffer update request
    my $socket = $self->socket;
    my $incremental = $self->_framebuffer ? 1 : 0;

    $incremental = 0;

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

sub capture {
    my $self   = shift;

    $self->_send_update_request();

    while ( ( my $message_type = $self->_receive_message() ) != 0 ) {
        warn $message_type;
    }

    return $self->_image_plus_cursor;
}

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

1;
