#!/usr/bin/perl

#       perl program to check heartbeat emails for protop clients.
#       if heartbeat email is not received within <delta> minutes of agreed time
#       then send an alert email.

our $VERSION = '1.00';

if( int(@ARGV) == 0 || grep( /^(-h|--help)$/i, @ARGV ) ){
   print "Example:\n";
   print "  pt3chkmail.pl --user username --pass password --subject string --folders \"INBOX/%\" --delta 10\n\n";
   print "Required arguments:\n";
   print "   --user username         : The username to log in to IMAP with\n";
   print "   --pass password         : The password to log in to IMAP with\n";
   print "   --passfile file         : An alternative to --pass. File contains the password\n";
   print "   --subject string        : Text to search for in Subject: header\n";
   print "   --folders f1 f2         : A list of folder search strings to find the folders\n";
   print "   --delta num             : Minutes to allow +/- expected time\n";
   print "Optional arguments:\n";
   print "   --ssl or --tls          : If you don't choose one of these it defaults to an\n";
   print "                             unencrypted connection\n";
   print "   --host ip.address       : Defaults to 127.0.0.1\n";
   print "   --port port             : Defaults to 143 or 993 depending on ssl/tls\n";
   print "   --test                  : Just display what *would* happen. Don't do the deletions\n\n";
   exit 0;
}


use strict;
use warnings;

# required modules
use Net::IMAP::Simple;
use Email::Simple;
use IO::Socket::SSL;
use Time::Piece;
use Time::Seconds;

## Parse the arguments
my %options;
{
   my @req = qw( user folders pass delta subject);
   my @opt = qw( host port ssl tls test passfile );

   my @arg = @ARGV;
   while( @arg ){
      my $key = shift @arg;
      if( $key =~ /^--(.+)$/ ){
         $key = $1;
         die "Bad arg: $key\n" unless grep($key eq $_, @req, @opt, );
         my @values = @{$options{$key}||[]};
         push @values, shift @arg while( int(@arg) && $arg[0]!~/^--/ );
         push @values, 1 unless int(@values);
         $options{$key}=\@values;
      } 
      else {
         die "Bad arg: $key\n";
      }
   }

   if( $options{passfile} ){
      open my $in, '<', $options{passfile}[0] or die $!;
      chomp( my $pass = <$in> );
      $options{pass} = [$pass];
      close $in;
   }

   foreach my $key ( @req ){
      die "Missing required argument: $key\n" unless exists $options{$key};
   }
}


my $user     = $options{user}[0];
my $pass     = $options{pass}[0];
my $delta    = $options{delta}[0];
my $subject  = $options{subject}[0];
my $host     = $options{host}[0];

my $connect_methods = exists $options{ssl} ? 'SSL' : exists $options{tls} ? 'STARTTLS' : 'PLAIN';

#	Connect
my $imap = Net::IMAP::Simple->new(
    $host,
    port    => 993,
    use_ssl => 1,
) || die "Unable to connect to IMAP: $Net::IMAP::Simple::errstr\n";

#	Log in
if ( !$imap->login( $user, $pass ) ) {
    print STDERR "Login failed: " . $imap->errstr . "\n";
    exit(64);
}
#	Look in the the INBOX
my $nm = $imap->select('INBOX');

#	How many messages are there?
my ($unseen, $recent, $num_messages) = $imap->status();
#print "unseen: $unseen, recent: $recent, total: $num_messages\n\n";

#	Isolate the messages we want to look at 
my $seekdate = calc_date(-86400);
my $lend = Time::Piece->new;
my $end = $lend->gmtime;
my $start = $end - (60 * $delta * 2);

print "Start UTC = $start\n  End UTC = $end\n    Delta = +/-$delta minutes\n\n";

my @ids = $imap->search("SUBJECT $subject SENTSINCE $seekdate" );
my $alive=0;
foreach my $msg (@ids) {
#  printf( "%s\t", $msg );
   my $es = Email::Simple->new( join '', @{ $imap->top($msg) } );

   my $maildate  = $es->header('Date');
   $maildate =~ s/([+\-]\d\d):(\d\d)/$1$2/;
#  print "maildate\t$maildate\n";

   my $mdate = Time::Piece->strptime($maildate,'%a, %d %b %Y %H:%M:%S %z');
   print "Email UTC = $mdate";
   if ($mdate ge $start and $mdate le $end){
      $alive=1;
      print "*";
   }
   print "\n";
}
unless ($alive){
   print "\nNo heartbeat found - press the panic button\n\n";
   $imap->quit;
   exit 1;
}
print "\nHeartbeat record found\n\n";

# Disconnect

$imap->quit;
exit;

sub calc_date {

   my ($days) = @_;
   my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
   my( $mday, $mon, $year, ) = ( localtime( time + $days ) )[3..5];
   return sprintf( '%s-%s-%s', $mday, $months[$mon], $year+1900, );
}
