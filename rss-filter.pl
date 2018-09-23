#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use HTTP::Tiny;
use Time::Piece;

my $opt_url;
my $opt_state  = '/tmp/state';
my $opt_output = '/tmp/filter.rss';
my $opt_filter;
my $opt_exec;
my $opt_verbose;
GetOptions(
    'url=s'    => \$opt_url,
    'state=s'  => \$opt_state,
    'exec=s'   => \$opt_exec,
    'filter=s' => \$opt_filter,
    'output=s' => \$opt_output,
    'verbose'  => \$opt_verbose
) or die("Error in command line arguments\n");

print STDERR "Mirroring $opt_url...\n" if $opt_verbose;

my $result = HTTP::Tiny->new->mirror( $opt_url, $opt_output );
die 'request failed' unless $result->{success};

my $rss = _slurp($opt_output);
my $state = -f $opt_state ? _slurp($opt_state) : undef;

my $rss_format =
  $rss =~ m/xmlns:atom/ ? 'atom' : $rss =~ m/<rdf:RDF/ ? 'rdf' : 'rss';

print STDERR "Detected format: $rss_format\n" if $opt_verbose;

if ( !$state ) {
    print STDERR "No state found, everything is new\n" if $opt_verbose;
}
else {
    print STDERR "Last state found: $state\n" if $opt_verbose;
}

my @items = $rss =~ m{<item.*?>(.*?)</item>}mscg;

print STDERR sprintf( "Found %d items\n", scalar @items ) if $opt_verbose;

my $first_date;
foreach my $item (@items) {
    my $date;

    if ( $item =~ m{<dc:date>(.*?)</dc:date>} ) {
        $date = $1;
    }
    elsif ( $item =~ m{<pubDate>(.*?)</pubDate>} ) {
        $date = $1;

        $date = Time::Piece->strptime( $date, "%a, %d %b %Y %H:%M:%S %z" )
          ->strftime('%F %T');
    }

    $first_date //= $date;

    if ( $state && $date le $state ) {
        last;
    }

    if ($opt_filter) {
        if ( $item =~ m/$opt_filter/i ) {
            print STDERR "Matched filter\n" if $opt_verbose;
        }
        else {
            print STDERR "Skipping\n" if $opt_verbose;
            next;
        }
    }

    my ($title) = $item =~ m{<title>(.*?)</title>}ms;
    my ($link)  = $item =~ m{<link>(.*?)</link>}ms;

    print STDERR "New item: $title\n" if $opt_verbose;

    if ($opt_exec) {
        $ENV{TITLE} = $title;
        $ENV{LINK}  = $link;

        print STDERR "Executing command: $opt_exec\n" if $opt_verbose;

        system($opt_exec);
    }
}

print STDERR "Saving state: $first_date\n" if $opt_verbose;

_spew( $opt_state, $first_date );

sub _slurp {
    do { local $/; open my $fh, '<', $_[0] or die $!; <$fh> }
}

sub _spew {
    open my $fh, '>', $_[0] or die $!;
    print $fh $_[1];
}
