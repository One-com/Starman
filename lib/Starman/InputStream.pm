use strict;
use warnings;

package Starman::InputStream;
our $CHUNKSIZE = 32 * 1024;

sub finalize {
    my $self = shift;

    # consume what's left
    my $buf='';
    while (1) { 
        my $read = $self->read($buf, $Starman::InputStream::CHUNKSIZE);
        die "Read error: $!\n" unless defined $read;
        last if $read == 0;
    }

    return $self->{inputbuf};
}


package Starman::InputStream::Identity;
use parent 'Starman::InputStream';

sub new {
    my($class, $socket, $length, $inputbuf) = @_;

    $inputbuf = '' unless defined $inputbuf;

    my $buflen = length $inputbuf;

    bless { socket => $socket, length => $length, inputbuf => $inputbuf }, $class;
}

sub read {
    my($self, $_buf, $len, $offset) = @_;
    $offset ||= 0;
    
    $_[1] = '' unless defined $_[1];
    
    return 0 if ($self->{EOF});

    # content-length has been specified
    $len = $self->{length} if $len > $self->{length};

    if (my $buflen = length $self->{inputbuf}) {
    
        $len = $buflen if $len > $buflen;
        substr $_[1], $offset, $len, (substr $self->{inputbuf}, 0, $len, '');
    } else {
        $len = sysread $self->{socket}, $_[1], $len, $offset;
        die "Read error: $!\n" unless (defined $len);
    }
    
    $self->{length} -= $len;
    return if $len == 0 && $self->{length} != 0; # return undef, connection closed before the entire body was read
    $self->{EOF} = 1 if $self->{length} == 0;
    return $len;
}

#-----------------------------------

package Starman::InputStream::Chunked;
use parent 'Starman::InputStream';

sub new {
    my($class, $socket, $inputbuf) = @_;
    # if length is defined then content-length has been specified
    # if length is undef then chunked transfer encoding is being used

    $inputbuf = '' unless defined $inputbuf;

    my $buflen = length $inputbuf;

    bless { socket => $socket, inputbuf => $inputbuf }, $class;
}

sub read {
    my($self, $_buf, $len, $offset) = @_;
    $offset ||= 0;
    
    $_[1] = '' unless defined $_[1];

    return 0 if ($self->{EOF});

    # chunked transfer encoding
    while (1) {
        if ( $self->{inputbuf} =~ /^(([0-9a-fA-F]+).*\015\012)/ ) {
            my $chunk_len   = hex $2;
            my $trailer_len = length $1;
            my $gross_len   = $trailer_len + $chunk_len + 2;

            if (length $self->{inputbuf} >= $gross_len) {
                # we have a complete chunk, we can now extract it from the inputbuf
                my $chunk = substr $self->{inputbuf}, $trailer_len, $chunk_len;
                substr $self->{inputbuf}, 0, $gross_len, '';

                if ($chunk_len == 0) {
                    $self->{EOF} = 1;
                    return 0;
                } else {
                    $len = $chunk_len if $len > $chunk_len;
                    substr $_[1], $offset, $len, (substr $chunk, 0, $len, '');

                    if (my $ch_l = length $chunk) {
                        $self->{inputbuf} = sprintf( "%x", $ch_l ) . "\r\n" . $chunk . "\r\n" . $self->{inputbuf};
                    }
                    return $len;
                }
            }
        }
        my $read = sysread $self->{socket}, my($data), $Starman::InputStream::CHUNKSIZE;
        die "Read error: $!\n" unless (defined $read);

        $self->{inputbuf} .= $data;
    }
}

1;
