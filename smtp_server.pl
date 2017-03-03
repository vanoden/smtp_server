#!/usr/bin/perl
###########################################################
### smtp_server.pl										###
### Homegrown SMTP Server for personal use.				###
### A. Caravello 12/12/2016								###
###########################################################

# Load Modules
use strict;
#use Porkchop::AccountList;
#use Porkchop::Account;
use IO::Socket;
use IO::Select;
use subs 'log';
use Time::HiRes qw( time );

###########################################################
### Configuration										###
###########################################################
my %config = (
	'hostname'	=> 'testme.mail.com',
	'address'	=> '127.0.0.1',
	'port'		=> 25,
	'protocol'	=> 'tcp',
	'log_level'	=> 9,
	'maildir'	=> '/export/maildir',
);

###########################################################
### Main Procedure										###
###########################################################
my %count;

my $socket = IO::Socket::INET->new(
	Listen		=> 5,
	LocalAddr	=> $config{address},
	LocalPort	=> $config{port},
	Proto		=> 'tcp',
	ReuseAddr	=> 1
);

# Select Input Stream
my $server_select = IO::Select->new();
$server_select->add($socket);

log("Ready");
while (1) {
	# Listener Ready for Action
	if ($server_select->exists($socket)) {
		my @connections_pending = $server_select->can_read(1);
		foreach (@connections_pending) {
			$count{connections} ++;
			my $fh;
			my $remote = accept($fh, $_);

			my($port,$iaddr) = sockaddr_in($remote);
			my $peeraddress = inet_ntoa($iaddr);

			#$ipc->increment('proxy::connections');
			handle_request($fh, $peeraddress);
		}
	}
	sleep .2;
}

###############################################
### SMTP Handler							###
### Takes SMTP Service threads, parses and	###
### returns response.						###
###############################################
sub handle_request {
	my ($client,$ip_address) = @_;

	my $request;

	my $start_time = time;
	log("Request from $ip_address");

	print STDOUT "SERVICE: handle_request()\n" if ($config{log_level} > 5);

	select $client;
	$| = 1;

	print "220 testmail.mine.com SMTP Mail Server Ready\r\n";
	while (1) {
		my $command = <$client>;
		if ($command =~ /^EHLO\s([\w\-\.]+)/) {
			$request->{hello} = $1;
			log("New Hello: ".$request->{hello}." from $ip_address");
			print "250-".$config{hostname}." Hello [$ip_address]\r\n";
		}
		elsif ($command =~ /^MAIL\sFROM\:\s?(.+)\r?\n/) {
			$request->{from_address} = lc($1);
			$request->{from_address} =~ s/(\r|\n)//g;

			unless ($request->{hello}) {
				print "123-EHLO REQUIRED\r\n";
				next;
			}
			
			log("MAIL FROM: ".$request->{from_address});
			if (valid_email($request->{from_address})) {
				$request->{from_address} =~ /(.+)\@(.+)/;
				$request->{from_account} = $1;
				$request->{from_domain} = $2;
				print "250 2.1.0 Sender OK\r\n";
			}
			else {
				log("INVALID ADDRESS",'notice');
				print "510 Bad Email Address\r\n";
				$request->{from_address} = undef;
			}
		}
		elsif ($command =~ /^RCPT\sTO\:\s?(.+)\r?\n/) {
			$request->{to_address} = lc($1);
			$request->{to_address} =~ s/(\r|\n)//g;

			log("RCPT TO: ".$request->{to_address});
			if (valid_email($request->{to_address})) {
				$request->{to_address} =~ /(.+)\@(.+)/;
				$request->{to_domain} = $2;
				$request->{to_account} = $1;

				if (! -d $config{maildir}."/".$request->{to_domain}) {
					log("DOMAIN NOT HOSTED",'notice');
					print "550 Non-existent email address\r\n";
					$request->{to_address} = undef;
				}
				elsif(! -d $config{maildir}."/".$request->{to_domain}."/".$request->{to_account}) {
					log("ACCOUNT NOT FOUND",'notice');
					print "550 Non-existent email address\r\n";
					$request->{to_address} = undef;
				}
				else {
					print "250 2.1.5 Recipient OK\r\n";
				}
			}
			else {
				log("INVALID ADDRESS",'notice');
				print "510 Bad Email Address\r\n";
				$request->{to_address} = undef;
			}
		}
		elsif ($command =~ /^QUIT/i) {
			print "221 closing connection\r\n";
			log("USER QUIT");
			return 1;
		}
		else {
			print "500-Sorry Invalid\r\n";
			log("INVALID COMMAND: ".$command);
		}

		if ($request->{hello} && $request->{from_address} && $request->{to_address}) {
			log("DATA ENTRY");
			print "DATA\r\n";
			print "354 Start mail input; end with <CRLF>.<CRLF>\r\n";

			my $incoming = '';
			while (1) {
				my $buffer = <$client>;
				if ($buffer =~ /^\.\r?\n$/) {
					log("END DATA ENTRY");
					# Store Contents
					my $file = $config{maildir}."/".$request->{to_domain}."/".$request->{to_account}."/".time;
					if (open(MESSAGE,"> $file")) {
						print MESSAGE "HELLO: ".$request->{hello}."\n";
						print MESSAGE "ADDRESS: ".$ip_address."\n";
						print MESSAGE "MAIL FROM: ".$request->{from_address}."\n";
						print MESSAGE "RCPT TO: ".$request->{to_address}."\n";
						print MESSAGE $incoming;
						close MESSAGE;
						log("Message Stored");
						print "250 Got it\r\n";
					}
					else {
						print "123-Error saving contents\r\n";
						log("Failed to open message file '$file': $!",'error');
					}
					$request->{from_address} = undef;
					$request->{to_address} = undef;
					last;
				}
				else {
					$incoming .= $buffer;
				}
			}
		}
	}

	###################################################
	### Response									###
	###################################################
	print "Go away, you smell funny\r\n";

	return 1;
}

sub log {
	my ($message,$level) = @_;
	$level = 'debug' unless ($level);
	$level = uc($level);
	print STDOUT "$level: $message\n";
}

sub valid_email {
	my $address = shift;
log("Checking '$address'");
	if ($address =~ /^[\w\.\_\%\+\-]+\@[\w\.\-]+\.[a-z]{2,}$/) {
		return 1;
	}
	return 0;
}
