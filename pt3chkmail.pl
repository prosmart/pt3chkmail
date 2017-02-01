#!/usr/bin/perl

#	perl program to check heartbeat emails for protop clients.
#	if heartbeat email is not received within <delta> minutes of agreed time
#	then send an alert email.

our $VERSION = '1.00';

use strict;
use warnings;
use IMAP::Client;

if( int(@ARGV) == 0 || grep( /^(-h|--help)$/i, @ARGV ) ){
   print "Example:\n";
   print "  pt3chkmail.pl --user username --pass password --subject "subject" --folders \"INBOX/%\" --delta 10\n\n";
   print "Required arguments:\n";
   print "   --user username         : The username to log in to IMAP with\n";
   print "   --pass password         : The password to log in to IMAP with\n";
   print "   --passfile file         : An alternative to --pass. File contains the password\n";
   print "   --subject string        : Text to search for in Subject: header";
   print "   --folders f1 f2         : A list of folder search strings to find the folders\n";
   print "   --delta num             : Delete emails over num days old\n\n";
   print "   --age num               : Delete emails over num days old\n\n";
   print "Optional arguments:\n";
   print "   --debug num             : Set a debug level from 1-9\n";
   print "   --ssl or --tls          : If you don't choose one of these it defaults to an\n";
   print "                           : unencrypted connection\n";
   print "   --host ip.address       : Defaults to 127.0.0.1\n";
   print "   --port port             : Defaults to 143 or 993 depending on ssl/tls\n";
   print "   --authas user           : To authenticate as a user other than the one in\n";
   print "                           : --user (If this doesn't make sense to you, you\n";
   print "                           : don't need it)\n";
   print "   --test                  : Just display what *would* happen. Don't do the deletions\n";
   exit 0;
}


## Parse the arguments
  my %options;
  {
     my @req = qw( user folders age pass delta subject);
     my @opt = qw( debug host port ssl tls authas test passfile );

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
        } else {
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

my $user   = $options{user}[0];
my $pass   = $options{pass}[0];
my $connect_methods = exists $options{ssl} ? 'SSL' : exists $options{tls} ? 'STARTTLS' : 'PLAIN';

my $delta = $options{delta}[0];
die "Bad delta: $delta\n" unless $delta =~ /^-?\d+$/;

#my $age = $options{age}[0];
#die "Bad age: $age\n" unless $age =~ /^-?\d+$/;

## Connect via IMAP
  my $imap;
  {
     my %args = ( ConnectMethod => $connect_methods );
     $args{PeerAddr} = exists $options{host} ? $options{host}[0] : '127.0.0.1';
     if( exists $options{port} ){
        $args{IMAPPort}  = $options{port}[0];
        $args{IMAPSPort} = $options{port}[0];
     }

     $imap = new IMAP::Client();
     $imap->debuglevel( $options{debug}[0] ) if exists $options{debug};
     $imap->connect( %args ) or die $imap->error;
     if( exists $options{authas} ){
        $imap->authenticate( $user, $pass, $options{authas}[0] ) or die $imap->error;
     } else {
        $imap->login( $user, $pass, ) or die $imap->error;
     }
  }

my @folders = ();
foreach my $item ( @{$options{folders}} ){
   my $results = $imap->list('',$item);
   
   foreach my $folder ( map {$_->{MAILBOX}} @$results ){
      push @folders, $folder unless grep( $folder eq $_, @folders, );
   }
}

if( exists $options{test} ){
   print "TEST  : You're running in test mode, so the actions wont actually take place\n";
}
print "ACTION: Check mail which arrived before ".begin_date($age)." from: ".join(", ", @folders)."\n";

foreach my $folder ( @folders ){

   ## Select the mailbox and check that it contains at least 1 email
     my %info = $imap->select( $folder ) or die "$folder: ".$imap->error;
     next unless $info{EXISTS};

    ## Search for mail older than a certain date
      my @uids = $imap->uidsearch( 'SUBJECT '$subject 'ON '.begin_date($age) );
      next unless @uids;

    ## Check the mail
      unless( exists $options{test} ){
         while( @uids ){
            my @foo = ();
            while( @uids && int(@foo) < 1000 ){
               push @foo, shift @uids;
            }
            $imap->uidstore(join(',',@foo),'+FLAGS.SILENT',$imap->buildflaglist('\Deleted'));
            $imap->expunge();
         }
      }
}

sub begin_date {
   my $days = $_[0]-1;

   my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
   my( $mday, $mon, $year, ) = ( localtime( time - ($days*86400) ) )[3..5];
   return sprintf( '%s-%s-%s', $mday, $months[$mon], $year+1900, );
}
