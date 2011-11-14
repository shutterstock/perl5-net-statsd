package Net::Statsd;

# ABSTRACT: Sends statistics to the stats daemon over UDP
# Cosimo Streppone <cosimo@cpan.org>

use strict;
use warnings;
use IO::Socket ();

our $HOST = 'localhost';
our $PORT = 8125;

=head1 NAME

Net::Statsd - Perl client for Etsy's statsd daemon

=head1 SYNOPSIS

    # Configure where to send events
    # That's where your statsd daemon is listening.
    $Net::Statsd::HOST = 'localhost';    # Default
    $Net::Statsd::PORT = 8125;           # Default

    #
    # Keep track of events as counters
    #
    Net::Statsd::increment('site.logins');
    Net::Statsd::increment('database.connects');

    #
    # Log timing of events, ex. db queries
    #
    use Time::HiRes;
    my $start_time = [ Time::HiRes::gettimeofday ];

    # do the complex database query
    Net::Statsd::timing(
        'database.complexquery',
        Time::HiRes::tv_interval($start_time)
    );

=head1 DESCRIPTION

This module implement a UDP client for the B<statsd> statistics
collector daemon in use at Etsy.com.

You want to use this module to track statistics in your Perl
application, such as how many times a certain event occurs
(user logins in a web application, or database queries issued),
or you want to time and then graph how long certain events take,
like database queries execution time or time to download a
certain file, etc...

If you're uncertain whether you'd want to use this module or
statsd, then you can read some background information here:

    http://codeascraft.etsy.com/2011/02/15/measure-anything-measure-everything/

The github repository for statsd is:

    http://github.com/etsy/statsd

By default the client will try to send statistic metrics to
C<localhost:8125>, but you can change the default hostname and port
with:

    $Net::Statsd::HOST = 'your.statsd.hostname.net';
    $Net::Statsd::PORT = 9999;

just after including the C<Net::Statsd> module.

=head1 FUNCTIONS

=cut

=head2 C<timing($stat, $time, $sample_rate = 1)>

Log timing information.
Time is assumed to be in milliseconds (ms).

    Net::Statsd::timing('some.time', 500);

=cut

sub timing {
    my ($stat, $time, $sample_rate) = @_;

    my $stats = {
        $stat => sprintf "%d|ms", $time
    };

    return Net::Statsd::send($stats, $sample_rate);
}

=head2 C<increment($stats, $sample_rate=1)>

Increments one or more stats counters

    # +1 on 'some.int'
    Net::Statsd::increment('some.int');

    # 0.5 = 50% sampling
    Net::Statsd::increment('some.int', 0.5);

To increment more than one counter at a time,
you can B<pass an array reference>:

    Net::Statsd::increment(['grue.dinners', 'room.lamps'], 1);

B<You can also use "inc()" instead of "increment()" to type less>.

=cut

sub increment {
    my ($stats, $sample_rate) = @_;

    return Net::Statsd::update_stats($stats, 1, $sample_rate);
}

*inc = *increment;

=head2 C<decrement($stats, $sample_rate=1)>

Same as increment, but decrements. Yay.

    Net::Statsd::decrement('some.int')

B<You can also use "dec()" instead of "decrement()" to type less>.

=cut

sub decrement {
    my ($stats, $sample_rate) = @_;

    return Net::Statsd::update_stats($stats, -1, $sample_rate);
}

*dec = *decrement;

=head2 C<update_stats($stats, $delta=1, $sample_rate=1)>

Updates one or more stats counters by arbitrary amounts

    Net::Statsd::update_stats('some.int', 10)

equivalent to:

    Net::Statsd::update_stats('some.int', 10, 1)

A sampling rate less than 1 means only update the stats
every x number of times (0.1 = 10% of the times).

=cut

sub update_stats {
    my ($stats, $delta, $sample_rate) = @_;

    $delta = 1 unless defined $delta;
    $sample_rate = 1 unless defined $sample_rate;

    if (! ref $stats) {
        $stats = [ $stats ];
    }
    elsif (ref $stats eq 'HASH') {
        Carp::croak("Usage: update_stats(\$str, ...) or update_stats(\\\@list, ...)");
    }

    my %data = map { $_ => sprintf "%s|c", $delta } @{ $stats };

    return Net::Statsd::send(\%data, $sample_rate)
}

=head2 C<send(\%data, $sample_rate=1)>

Squirt the metrics over UDP.

    Net::Statsd::send({ 'some.int' => 1 });

=cut

sub send {
    my ($data, $sample_rate) = @_;

    my %sampled_data;

    if ($sample_rate < 1) {
        if (rand() <= $sample_rate) {
            while (my ($stat, $value) = each %{ $data }) {
                $sampled_data{$stat} = sprintf "%s|@%s", $value, $sample_rate;
            }
        }
    }
    else {
        %sampled_data = %{ $data };
    }

    my $udp_sock = IO::Socket::INET->new(
        Proto    => 'udp',
        PeerAddr => $HOST,
        PeerPort => $PORT,
    ) or return;

    # We don't want to die if Net::Statsd::send() doesn't work...
    # We could though:
    #
    # or die "Could not create UDP socket: $!\n";

    my $all_sent = 1;

    for my $stat (keys %sampled_data) {
        my $value =$data->{$stat};
        my $packet = "$stat:$value";
        $udp_sock->send($packet);
        # XXX If you want warnings...
        # or do {
        #    warn "[" . localtime() . "] UDP packet '$packet' send failed\n";
        #    $all_sent = 0;
        #};
    }

    return $all_sent;
}

unless (caller) {
    Net::Statsd::increment('test.counter1');
    Net::Statsd::increment('test.counter2');
    Net::Statsd::decrement('test.counter1');
    Net::Statsd::decrement('test.counter2');
}

1;
