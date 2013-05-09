use strict;
use warnings;
use threads;

use vars qw($VERSION %IRSSI);
$VERSION = '20120421b';
%IRSSI = (
	name		=> 'Proxy Monitor',
	authors		=> 'Iain Cuthbertson',
	contact		=> 'iain.cuthbertson@idophp.co.uk',
	url 		=> 'http://idophp.co.uk/',
	license		=> 'GPL',
	description	=> 'Monitor conntection/disconnect from proxy clients and send'
				. 'the backlog',
);
use Irssi qw(signal_add);

use File::Path qw(make_path remove_tree);

my @month_abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

sub proxy_disconnect
{
	Irssi::settings_set_str('proxy_logging', 1);

	my $network = $_[0]->{server};
	my $networkName = $network->{tag};

	Irssi::signal_add_last('message public', 'log_public_message');
	Irssi::signal_add_last('message private', 'log_private_message');

	print '+-- [proxy monitor] - started for: ' . $networkName;
}

sub proxy_connect
{
	Irssi::settings_set_str('proxy_logging', 0);

	my $network = $_[0]->{server};
	my $networkName = $network->{tag};

	Irssi::signal_remove('message public', 'log_public_message');
	Irssi::signal_remove('message private', 'log_private_message');

	print '+-- [proxy monitor] - stopped for: ' . $networkName;

	my $thr = threads->create('send_backlog', $network);
}

sub log_public_message
{
	my $loggingActive = Irssi::settings_get_str('backlog_path');

	if ($loggingActive)
	{
		my $network = $_[0];
		my $networkName = $network->{tag};
		my $channel = $_[4];
		my $nick = $_[2];
		my $msg = $_[1];

		my $backlogPath = Irssi::settings_get_str('backlog_path');
		my $backlogDir = $backlogPath . '/' . $networkName;

		unless(-d $backlogDir)
		{
			mkdir $backlogDir or die $!;
		}

		my $backlogFile = $backlogDir . '/' . $channel . '.log';

		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$year += 1900;
		my $formattedDateTime = "$mday $month_abbr[$mon] $year $hour:$min";

		open (BACKLOG, '>>' . $backlogFile);
		print BACKLOG "(" . $formattedDateTime . ") <" . $nick . "> " . $msg . "\n";
		close (BACKLOG);
	}

}

sub send_backlog
{
	my $network = $_[0];
	my $networkName = $network->{tag};

	sleep(2); #Allow the client to connect

	my $backlogPath = Irssi::settings_get_str('backlog_path');
	my $backlogDir = $backlogPath . '/' . $networkName;

	if (-d $backlogDir)
	{
		print '+-- [proxy monitor] - backlog for network: ' . $networkName . ' [START]';

		opendir (DIR, $backlogDir) or die $!;
		Irssi::signal_add_first('print text', 'stop_sig');

		while (my $channelFile = readdir(DIR))
		{
			my $backlogFile = $backlogDir . '/' . $channelFile;
			my $channelName = substr($channelFile, 0, -4);

			if (-f $backlogFile)
			{
				open FILE, "<", $backlogDir . '/' . $channelFile or die $!;
				while (<FILE>)
				{
					if (substr($channelName, 0, 1) eq "#")
					{
						Irssi::signal_emit('server incoming', $network, ':proxy NOTICE ' . $channelName .' :' . $_);
					}
					else
					{
						#Query
						Irssi::signal_emit('server incoming', $network, ':'.$channelName.' PRIVMSG blue112 :'.$_);
					}
				}
			}
		}
		Irssi::signal_remove('print text', 'stop_sig');
		print '+-- [proxy monitor] - backlog for network: ' . $networkName . ' [END]';
	}

	wipe_backlog($network);
}

sub log_private_message
{
	my $network = $_[0];
	my $networkName = $network->{tag};
	my $nick = $_[2];
	my $msg = $_[1];

	my $backlogPath = Irssi::settings_get_str('backlog_path');
	my $backlogDir = $backlogPath . '/' . $networkName;

	unless(-d $backlogDir)
	{
		mkdir $backlogDir or die $!;
	}

	my $backlogFile = $backlogDir . '/' . $nick . '.log';

	open (BACKLOG, '>>' . $backlogFile);
	print BACKLOG "(".localtime() . ") " $msg;
	close (BACKLOG);
}

sub stop_sig
{
	Irssi::signal_stop();
}

sub wipe_backlog
{
	my $network = $_[0];
	my $networkName = $network->{tag};

	my $backlogPath = Irssi::settings_get_str('backlog_path');
	my $backlogDir = $backlogPath . '/' . $networkName;

	if (-d $backlogDir)
	{
		remove_tree($backlogDir);

		print '+-- [proxy monitor] - backlog removed for network: ' .$networkName;
	}
}

Irssi::settings_add_str('proxy_monitor', 'backlog_path', '/var/www/.irssi/proxy_monitor');

Irssi::settings_add_str('proxy_monitor', 'proxy_logging', 1);

Irssi::signal_add_last('proxy client disconnected', 'proxy_disconnect');
Irssi::signal_add_last('proxy client connected', 'proxy_connect');

