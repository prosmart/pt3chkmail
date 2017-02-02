#!/usr/bin/perl


use strict;
use warnings;

# required modules
use Net::IMAP::Simple;
use Email::Simple;
use IO::Socket::SSL;

# fill in your details here
my $username = 'dna@openedgesolutions.com.au';
my $password = 'D0th3macar3na';
my $mailhost = 'mail.openedgesolutions.com.au';
my $delta = 5;

# Connect
my $imap = Net::IMAP::Simple->new(
    $mailhost,
    port    => 993,
    use_ssl => 1,
) || die "Unable to connect to IMAP: $Net::IMAP::Simple::errstr\n";

# Log in
if ( !$imap->login( $username, $password ) ) {
    print STDERR "Login failed: " . $imap->errstr . "\n";
    exit(64);
}
# Look in the the INBOX
my $nm = $imap->select('INBOX');

# How many messages are there?
my ($unseen, $recent, $num_messages) = $imap->status();
print "unseen: $unseen, recent: $recent, total: $num_messages\n\n";

#	Isolate the message we want to look at 

my @ids = $imap->search('SUBJECT "Re: New Task"');

foreach my $msg (@ids) {
   printf( "%s\t", $msg );
   my $es = Email::Simple->new( join '', @{ $imap->top($msg) } );
   my $ddate  = $es->header('Date');
   printf ("%s\n", $ddate);
   #printf( "[%03d] %s\n\t%s\n\t%s\n", $msg, $es->header('From'), $es->header('Subject'), $es->header('Date'));

}

# Disconnect
$imap->quit;
exit;

sub begin_date {
   my $days = $_[0]-1;

   my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
   my( $mday, $mon, $year, ) = ( localtime( time - ($days*86400) ) )[3..5];
   printf( '%s-%s-%s', $mday, $months[$mon], $year+1900, );
}
