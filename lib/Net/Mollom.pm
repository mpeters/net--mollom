package Net::Mollom;
use Squirrel;
use XML::RPC;
use DateTime;
use Params::Validate qw(validate SCALAR);
use Digest::HMAC_SHA1 qw(hmac_sha1);
use MIME::Base64 qw(encode_base64);
use DateTime;
use Carp qw(carp croak);
use Net::Mollom::ContentCheck;

has current_server => (is => 'rw', isa => 'Num', default  => 0);
has public_key     => (is => 'rw', isa => 'Str', required => 1);
has private_key    => (is => 'rw', isa => 'Str', required => 1);
has session_id     => (is => 'rw', isa => 'Str');
has xml_rpc        => (is => 'rw', isa => 'XML::RPC');

our @SERVERS = (
    'http://xmlrpc1.mollom.com', 
    'http://xmlrpc2.mollom.com', 
    'http://xmlrpc3.mollom.com',
);
our $SERVERS_INITIALIZED = 0;
our $API_VERSION         = '1.0';
our $VERSION             = '0.01';

my $ERROR_PARSE           = 1000;
my $ERROR_REFRESH_SERVERS = 1100;
my $ERROR_NEXT_SERVER     = 1200;

=head1 NAME

Net::Mollom - interface with Mollom web API

=head1 SYNOPSIS

Communicate with the Mollom web API (L<http://mollom.com/>) via
XML-RPC to determine whether user input is Spam, Ham, flame or
obscene.

    my $mollom = Net::Mollom->new(
        public_key => 'a2476604ffba00c907478c8f40b83b03',
        private_key => '42d5448f124966e27db079c8fa92de0f',
    );

    my @server_list = $mollom->server_list();

    my $check = $mollom->check_content(
        post_title => $title,
        post_body  => $text,
    );
    if( $check->is_spam ) {
        warn "someone's trying to sell us v1@grA!"
    } elsif( $check->is_unsure ) {
        # show them a CAPTCHA to see if they are really human
        my $captcha_url = $mollom->get_image_captcha();
    } elsif( $check->quality < .5 ) {
        warn "someone's trying to flame us!"
    }

If you have any questions about how any of the methods work, please
consult the Mollom API documentation - L<http://mollom.com/api>.

=head1 CONSTRUCTORS

=head2 new

This creates a new NET::Mollom object for communication. It takes the following
named arguments:

=over

=item * public_key (required)

This is your Mollom API public key.

=item * private_key (required)

This is your Mollom API private key.

=back

=head1 METHODS

=head2 verify_key

Check to make sure that Mollom recognizes your public and private keys.
Returns true if successful, false otherwise. This is not necessary to use
in your application, but can be used when doing initial development or testing.

    if( $mollom->verify_key ) {
        # go a head and do stuff
    } else {
        # doh! you screwed up somewhere
    }

=cut

sub verify_key {
    my $self = shift;
    # get the server list from Mollom if we don't already have one
    $self->server_list() unless $SERVERS_INITIALIZED;
    return $self->_make_api_call('verifyKey');
}

=head2 check_content

Check some content for spamminess and quality. Takes the following
optional named arguments:

=over

=item * post_title

=item * post_body

=item * author_name

=item * author_url

=item * author_mail

=item * author_openid

=item * author_ip

=item * author_id

=back

Returns a L<Net::Mollom::ContentCheck> object.

    my $check = $mollom->check_content(
        post_title => $title,
        post_body => $body,
        author_name => 'Michael Peters',
        author_mail => 'mpeters@p3.com',
        author_id => 12345,
    );

=cut

sub check_content {
    my $self = shift;
    my %args = validate(
        @_,
        {
            post_title    => {type => SCALAR, optional => 1},
            post_body     => {type => SCALAR, optional => 1},
            author_name   => {type => SCALAR, optional => 1},
            author_url    => {type => SCALAR, optional => 1},
            author_mail   => {type => SCALAR, optional => 1},
            author_openid => {type => SCALAR, optional => 1},
            author_ip     => {type => SCALAR, optional => 1},
            author_id     => {type => SCALAR, optional => 1},
        }
    );

    # we need at least 1 arg
    croak "You must pass at least 1 argument to check_content!" unless %args;

    # get the server list from Mollom if we don't already have one
    $self->server_list() unless $SERVERS_INITIALIZED;
    my $results = $self->_make_api_call('checkContent', \%args);

    # remember the session_id so we can pass it along in future calls
    $self->session_id($results->{session_id});

    return Net::Mollom::ContentCheck->new(
        is_ham    => $results->{spam} == 1 ? 1 : 0,
        is_spam   => $results->{spam} == 2 ? 1 : 0,
        is_unsure => $results->{spam} == 3 ? 1 : 0,
        quality   => $results->{quality},
        session_id => $results->{session_id},
    );
}

=head2 send_feedback

Send feedback to Mollom about their rating of your content. Take sthe following
optional named parameters:

=over

=item * feedback

A string value of either C<spam>, C<profanity>, C<low-quality>, or C<unwanted>.

=item * session_id

The id of the session where the content was checed (by a call to C<check_content>).

=back

    $mollom->send_feedback

=cut 

sub send_feedback {
    my $self = shift;
    my %args = validate(
        @_,
        {
            feedback   => { type => SCALAR, regex => qr/^(spam|profanity|low-quality|unwanted)$/ },
            session_id => { type => SCALAR, optional => 1 },
        }
    );
    $args{session_id} ||= $self->session_id;

    # get the server list from Mollom if we don't already have one
    $self->server_list() unless $SERVERS_INITIALIZED;
    return $self->_make_api_call('sendFeedback', \%args);
}

=head2 get_image_captcha

Returns the URL of an image CAPTCHA. This should only be called if the last
message checked was marked C<is_unsure>. Not for C<is_spam> or C<is_ham>.
It takes the following optional parameters:

=over

=item * author_ip

The IP address of the content author

=item * session_id

The Mollom session_id. Normally you don't need to worry about this since Net::Mollom
will take care of it for you.

=back

=cut

sub get_image_captcha {
    my $self = shift;
    my %args = validate(
        @_,
        {
            author_ip  => { type => SCALAR, optional => 1 },
            session_id => { type => SCALAR, optional => 1 },
        }
    );
    $args{session_id} ||= $self->session_id;

    # get the server list from Mollom if we don't already have one
    $self->server_list() unless $SERVERS_INITIALIZED;
    my $results = $self->_make_api_call('getImageCaptcha', \%args);
    $self->session_id($results->{session_id});
    return $results->{url};
}

=head2 get_audio_captcha

Returns the URL of an audio CAPTCHA (mp3 file). This should only be called if the last
message checked was marked C<is_unsure>. Not for C<is_spam> or C<is_ham>.
It takes the following optional parameters:

=over

=item * author_ip

The IP address of the content author

=item * session_id

The Mollom session_id. Normally you don't need to worry about this since Net::Mollom
will take care of it for you.

=back

=cut

sub get_audio_captcha {
    my $self = shift;
    my %args = validate(
        @_,
        {
            author_ip  => { type => SCALAR, optional => 1 },
            session_id => { type => SCALAR, optional => 1 },
        }
    );
    $args{session_id} ||= $self->session_id;

    # get the server list from Mollom if we don't already have one
    $self->server_list() unless $SERVERS_INITIALIZED;
    my $results = $self->_make_api_call('getAudioCaptcha', \%args);
    $self->session_id($results->{session_id});
    return $results->{url};
}

=head2 server_list

This method will ask Mollom what servers to use. The list of servers
is saved in the Net::Mollom package and reused on subsequent calls
to the API. Normally you won't need to call this method on it's own
since it will be called for you when you use another part of the API.

    my @servers = $mollom->server_list();

    # or if you've saved the list in a more permanent data store
    $mollom->server_list(@servers);

=cut

sub server_list {
    my ($self, @list) = @_;
    if( @list ) {
        @SERVERS = @list;
        $self->current_server(0);
    } elsif(!$SERVERS_INITIALIZED) {
        # get our list from their API
        my $results = $self->_make_api_call('getServerList');
        @SERVERS = @$results;
        $SERVERS_INITIALIZED = 1;
        $self->current_server(0);
    }
    return @SERVERS;
}

=head2 get_statistics

This method gets your Mollom usage statistics. It takes the following required named
parameters:

=over

=item * type

Must be one of C<total_days>, C<total_accepted>, C<total_rejected>, C<yesterday_accepted>,
C<yesterday_rejected>, C<today_accepted>, C<today_rejected>.

=back

Will return the count for the specific statistic type you requested.

=cut

sub get_statistics {
    my $self = shift;
    my %args = validate(
        @_,
        {
            type => {
                type => SCALAR,
                regex =>
                  qr/^(total_(days|accepted|rejected)|yesterday_(accepted_rejected)|today_(accepted_rejected))$/
            },
        }
    );

    # get the server list from Mollom if we don't already have one
    $self->server_list() unless $SERVERS_INITIALIZED;
    return $self->_make_api_call('getStatistics', \%args);
}

sub _make_api_call {
    my ($self, $function, $args) = @_;
    my $secret = $self->private_key;

    if (!$self->xml_rpc) {
        $self->xml_rpc(XML::RPC->new($SERVERS[$self->current_server] . '/' . $API_VERSION));
    }

    $args->{public_key} ||= $self->public_key;
    $args->{time}       ||= DateTime->now->strftime('%Y-%m-%dT%H:%M:%S.000%z');
    $args->{nonce}      ||= int(rand(2_147_483_647));                          # rand 32 bit integer
    $args->{hash} ||=
      encode_base64(hmac_sha1(join(':', $args->{time}, $args->{nonce}, $secret), $secret));

    if (   $function ne 'getServerList'
        && $function ne 'verifyKey'
        && $function ne 'getStatistics'
        && $self->session_id)
    {
        $args->{session_id} = $self->session_id;
    }

    my $results = $self->xml_rpc->call("mollom.$function", $args);

    # check if there are any errors and handle them accordingly
    if (ref $results && (ref $results eq 'HASH') && $results->{faultCode}) {
        my $fault_code = $results->{faultCode};
        if ($fault_code == $ERROR_REFRESH_SERVERS) {
            if ($function eq 'getServerList') {
                croak("Could not get list of servers from Mollom!");
            } else {
                $SERVERS_INITIALIZED = 0;
                $self->server_list;
                return $self->_make_api_call($function, $args);
            }
        } elsif ($fault_code == $ERROR_NEXT_SERVER) {
            carp("Mollom server busy, trying the next one.");
            my $next_index = $self->current_server + 1;
            if ($#SERVERS <= $next_index) {
                $self->current_server($next_index);
                return $self->_make_api_call($function, $args);
            } else {
                croak("No more servers to try!");
            }
        } else {
            croak(
                "Error communicating with Mollom [$results->{faultCode}]: $results->{faultString}");
        }
    } else {
        return $results;
    }
}

=head1 AUTHOR

Michael Peters, C<< <mpeters at plusthree.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-net-mollom at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-Mollom>.  I will
be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Mollom

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-Mollom>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-Mollom>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-Mollom>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-Mollom/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Michael Peters, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Net::Mollom
