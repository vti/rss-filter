#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use HTTP::Tiny;

my $opt_url;
my $opt_state = '/tmp/state';
my $opt_rss   = '/tmp/filter.rss';
my $opt_filter;
my $opt_exec;
my $opt_verbose;
GetOptions(
    'url=s'    => \$opt_url,
    'state=s'  => \$opt_state,
    'exec=s'   => \$opt_exec,
    'filter=s' => \$opt_filter,
    'verbose'  => \$opt_verbose
) or die("Error in command line arguments\n");

print STDERR "Mirroring $opt_url...\n" if $opt_verbose;

my $result = HTTP::Tiny->new->mirror( $opt_url, $opt_rss );
die 'request failed' unless $result->{success};

my $rss = _slurp($opt_rss);
my $state = -f $opt_state ? _slurp($opt_state) : undef;

if ( !$state ) {
    print STDERR "No state found, everything is new\n" if $opt_verbose;
}
else {
    print STDERR "Last state found: $state\n" if $opt_verbose;
}

my @items = $rss =~ m{<item .*?>(.*?)</item>}mscg;

print STDERR sprintf( "Found %d items\n", scalar @items ) if $opt_verbose;

my $first_date;
foreach my $item (@items) {
    my ($date) = $item =~ m{<dc:date>(.*?)</dc:date>};

    $first_date //= $date;

    if ( $state && $date le $state ) {
        last;
    }

    if ($opt_filter) {
        if ( $item =~ m/$opt_filter/ ) {
            print STDERR "Matched filter\n" if $opt_verbose;
        }
        else {
            print STDERR "Skipping\n" if $opt_verbose;
            next;
        }
    }

    print STDERR "New item: $item\n" if $opt_verbose;

    if ($opt_exec) {
        my ($title) = $item =~ m{<title>(.*?)</title>}ms;
        my ($link)  = $item =~ m{<link>(.*?)</link>}ms;

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
