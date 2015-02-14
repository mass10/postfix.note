#!/usr/bin/perl
# coding: utf-8

use strict;
use Sendmail::PMilter;
use Data::Dumper;
use Proc::Daemon;
use File::Spec::Functions;
use Getopt::Long;
use Cwd;
use Time::HiRes;








###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
package out;

sub println {

	print(@_, "\n");
}









###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
package util;

sub get_timestamp {
	
	my ($sec1, $usec) = Time::HiRes::gettimeofday();
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdat) = localtime($sec1);
	my $msec = int($usec / 1000);
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d.%03d',
		1900 + $year, 1 + $mon, $mday, $hour, $min, $sec, $msec);
}

sub getpid {

	return $$;
}









###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
package logger;

sub info {

	my $timestamp = util::get_timestamp();
	my $stream = undef;
	open($stream, '>>filter.log');
	print($stream $timestamp, ' (', util::getpid(), ') [info] ', @_, "\n");
	close($stream);
}








###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
package my_filter;

my $_state = 1;

sub quit {

	$_state = 0;
}

sub alive {

	return $_state;
}

sub close {

	my ($ctx) = @_;



	logger::info('<close()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub connect {

	my ($ctx) = @_;



	logger::info('<connect()> $$$ OPENNING A NEW CONNECTION FOR SMTP $$$');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub helo {

	my ($ctx) = @_;



	logger::info('<helo()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub abort {

	my ($ctx) = @_;



	logger::info('<abort()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub envfrom {

	my ($ctx) = @_;



	logger::info('<envfrom()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub envrcpt {

	my ($ctx) = @_;



	logger::info('<envrcpt()>');

	my $rcpt_addr = $ctx->getsymval('{rcpt_addr}');
	logger::info('<envrcpt()> recpt: [', $rcpt_addr, ']');

	if(0) {

		my $secret_recipients = {
			'xxx@example.jp' => 1
		};

		if(1 == $secret_recipients->{$rcpt_addr}) {
			return Sendmail::PMilter::SMFIS_REJECT;
		}
	}

	return Sendmail::PMilter::SMFIS_ACCEPT;
}

sub header {

	my ($ctx) = @_;



	logger::info('<header()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub eoh {

	my ($ctx) = @_;



	logger::info('<eoh()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub body {

	my ($ctx) = @_;



	logger::info('<body()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub eom {

	my ($ctx) = @_;



	logger::info('<eom()>');

	return Sendmail::PMilter::SMFIS_CONTINUE;
}

sub run {

	foreach my $sign ('INT', 'TERM', '') {
		$SIG{$sign} = \&main::_on_signal;
	}

	logger::info('### start ###');

	{
		my $callbacks = {
			close => \&my_filter::close,
			connect => \&my_filter::connect,
			helo => \&my_filter::helo,
			abort => \&my_filter::abort,
			envfrom => \&my_filter::envfrom,
			envrcpt => \&my_filter::envrcpt,
			header => \&my_filter::header,
			eoh => \&my_filter::eoh,
			body => \&my_filter::body,
			eom => \&my_filter::eom
		};

		my $milter = new Sendmail::PMilter();
		# $milter->auto_setconn('inet:10026@127.0.0.1', '/etc/postfix/main.cf');
		$milter->setconn('inet:10025@127.0.0.1');
		$milter->register('myfilter', $callbacks, Sendmail::Milter::SMFI_CURR_ACTS);
		#$milter->register('myfilter', $callbacks, Sendmail::Milter::SMFI_V2_ACTS);
		$milter->main();
	}

	logger::info('exit. (', $@, ')');
	logger::info('--- end ---');
}













###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
package my_daemon;

sub new {

	my ($name) = @_;
	my $work_dir = Cwd::getcwd();
	my $rundir = '/var/run';
	my $this = bless({}, $name);
	my $pidfile = File::Spec::Functions::catfile($rundir, 'pidfile.pid');
	my $core = Proc::Daemon->new(
		pid_file => $pidfile,
		work_dir => $work_dir
	);
	$this->{'.core'} = $core;
	$this->{'.pidfile'} = $pidfile;
	return $this;
}

sub core {

	my ($this) = @_;
	return $this->{'.core'};
}

sub create_daemon {

	my ($this) = @_;
	my $pid = $this->core()->Init();
	$this->{'.child'} = $pid;
	return $pid;
}

sub pid {

	my ($this) = @_;
	my $pidfile = $this->{'.pidfile'};
	return $this->core()->Status($pidfile);
}

sub kill {

	my ($this) = @_;
	my $pidfile = $this->{'.pidfile'};
	my $pid = $this->core()->Status($pidfile);
	out::println("Stopping pid $pid...");
	if(!$this->core()->Kill_Daemon($pidfile, 2)) {
		return 0;
	}
	return 1;
}

sub DESTROY {

	my ($this) = @_;
}













###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
###############################################################################
package main;

sub _on_signal {

	my ($signal) = @_;
	logger::info('caught signal [', $signal, ']');
	my_filter::quit();
}

sub _start {

	my $service = new my_daemon;

	my $pid = $service->pid();
	if($pid) {
		out::println('already running...');
		return;
	}

	if($service->create_daemon()) {
		# 呼び出し側(このプロセスはここで終了する)
		return;
	}

	my_filter::run();
}

sub _status {

	my $service = new my_daemon;

	my $pid = $service->pid();
	if(!$pid) {
		out::println('not running.');
		return;
	}

	out::println("Running with pid $pid.");
}

sub _stop {

	my $service = new my_daemon;

	my $pid = $service->pid();
	if(!$pid) {
		out::println('not running.');
		return;
	}

	if(!$service->kill()) {
		out::println("Could not find $pid. Was it running?");
		return;
	}

	out::println('Successfully stopped.');
}

sub _usage {

	out::println('usage:');
	out::println('    --help: show this message.');
	out::println('    --start: start.');
	out::println('    --stop: stop.');
	out::println();
}

sub _main {

	my $action_help = '';
	my $action_start = '';
	my $action_status = '';
	my $action_stop = '';

	if(!Getopt::Long::GetOptions(
		'help!' => \$action_help,
		'start!' => \$action_start,
		'status!' => \$action_status,
		'stop!' => \$action_stop
	)) {
		_usage();
		return;
	}

	if($action_help) {
		_usage();
	}
	elsif($action_stop) {
		_stop();
	}
	elsif($action_status) {
		_status();
	}
	elsif($action_start) {
		_start();
	}
	else {
		_usage();
	}
}

_main(@ARGV);

