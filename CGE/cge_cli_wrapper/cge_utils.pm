#!/usr/bin/env perl

package CGE::cge_cli_wrapper::cge_utils;

use strict;
use 5.016;
use IPC::Cmd qw(can_run run);
use Carp qw(croak cluck carp);
use YAML::AppConfig;
use POSIX;
use File::Path::Tiny;
use Data::Dumper;
use FindBin;
require Exporter;

our $VERSION = 0.01;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(add_user modify_user checkPid);
our %EXPORT_TAGS = (ALL => [ qw(add_user modify_user checkPid) ]);

#=+ Need to be able to run ssh-keygen
my $ssh_keygen = can_run('ssh-keygen');
my $mrun = can_run('mrun');

sub add_user {
  my($config_ref) = @_;

  #=+ default settings
  my %config = (
    username      => '',
    database_path => '',   #=+ Need to know the path to the directory we want to add a user to
    bits          => 2048,
    permissions   => 'ro'  #=+ Possible permissions are: read-only (ro), read-write (rw), admin (admin)
  );

  #=+ Take user-supplied options and replace defaults.  Maybe overkill, but we only allow expected settings
  while(my($k,$v) = each %$config_ref) {
    $config{$k} = $v if exists $config{$k};
  }

  #=+ Need to do some validation and make sure the permissions are acceptable
  return undef unless $config{permissions} =~ /^rw$|^ro$|^admin$/;

  #=+ Well, we are not going to get very far if we don't know who to generate a key pair for or which database
  return undef if $config{username} eq '' || $config{database_path} eq '';

  #=+ Make sure the database directory has a trailing slash
  $config{database_path} .= '/' unless $config{database_path} =~ /\/$/;
  my $authorized_users_dir = $config{database_path}.'.cge_web_ui/authorized_users/'.$config{username}.'/';

  #=+ Make sure our directory for authorized users exists
  File::Path::Tiny::mk($authorized_users_dir);

  #=+ Create a file with the user's permissions
  my $property_file = $authorized_users_dir.'properties.yaml';
  my $yaml = YAML::AppConfig->new();
  $yaml->set('username',$config{username});
  $yaml->set('database_path',$config{database_path});
  $yaml->set('permissions',$config{permissions});

  #=+ Need to track when the record was created and last modified
  my $datestring = strftime("%Y-%m-%d %H:%M:%S",localtime(time));
  $yaml->set('created',$datestring);
  $yaml->set('last_modified',$datestring);

  $yaml->dump($property_file);

  #=+ Now generate an RSA key pair
  my $success = run(command => $ssh_keygen.' -N \'\' -f '.$authorized_users_dir.'id_rsa');
  if($success) {
    open(my $PUBLIC, '<',$authorized_users_dir.'id_rsa.pub');
    my $public_key = <$PUBLIC>;
    chomp $public_key;
    close($PUBLIC);

    open(my $AUTHORIZED_KEYS, '>>',$config{database_path}.'/authorized_keys');
    say {$AUTHORIZED_KEYS} $public_key;
    close($AUTHORIZED_KEYS);
  }
  else {
    return undef;
  }
  return 1;
}

sub modify_user {
  my($changes_ref) = @_;

  #=+ Keeping with our pattern of a default structure to work with
  my %changes = (
    action        => '', #=+ Can be one of 'modify' or 'revoke': MANDATORY
    username      => '', #=+ MANDATORY
    permissions   => '', #=+ These will be the new permissions.  Same as before: ro, rw, or admin
    database_path => ''
  );

  #=+ Take user-supplied options and replace defaults.  Maybe overkill, but we only allow expected settings
  while(my($k,$v) = each %$changes_ref) {
    $changes{$k} = $v if exists $changes{$k};
  }

  #=+ Need to do some validation and make sure the permissions are acceptable
  return undef if ($changes{action}  eq 'modify' && $changes{permissions} !~ /^rw$|^ro$|^admin$/);
  return undef if $changes{action}   eq '' ||
                  $changes{username} eq '' ||
                  $changes{database_path} eq '' ||
                  ($changes{action}  eq 'modify' && $changes{permissions} eq '');

  #=+ Make sure the database directory has a trailing slash
  $changes{database_path} .= '/' unless $changes{database_path} =~ /\/$/;
  my $authorized_users_dir = $changes{database_path}.'.cge_web_ui/authorized_users/'.$changes{username}.'/';

  if($changes{action} eq 'revoke') {
    #=+ Remove the user from the authorized_keys file
    open (my $KEYFILE,'<',$authorized_users_dir.'id_rsa.pub');
    my $rsakey = <$KEYFILE>;
    close($KEYFILE);
    my $new_string;
    open(my $FH,'<',$changes{database_path}.'authorized_keys');
    while(my $line = <$FH>) {
      $new_string .= $line unless $line =~ /\Q$rsakey\E/;
    }
    close($FH);
    open($FH,'>',$changes{database_path}.'authorized_keys');
    say {$FH} $new_string;
    close($FH);

    #=+ Delete the user directory in authorized_users directory
    File::Path::Tiny::rm($authorized_users_dir);

  }
  elsif($changes{action} eq 'modify') {
    my $property_file = $authorized_users_dir.'properties.yaml';
    my $yaml = YAML::AppConfig->new(file => $property_file);
    my $datestring = strftime("%Y-%m-%d %H:%M:%S",localtime(time));
    $yaml->set('permissions',$changes{permissions});
    $yaml->set('last_modified',$datestring);
    $yaml->dump($property_file);
  }
  else {
    return undef;
  }
}

sub checkPid {
  my ($pid) = @_;
  my ($success,$error_message,$full_buf,$stdout_buf,$stderr_buf) = run(command => $mrun.' --info', verbose => 0);
  if($success) {
    #=+ Join the stdout buffer into one array and split on newlines so we have one line per element
    my @stdout_array = split(/\n/,join('',@$stdout_buf));
    
    foreach my $line(@stdout_array) {
      if($line =~ /$pid/) {
        return $pid;
      }
    }
    return undef;
  }
  else {
    return undef;
  }
}
1;

__END__

'TMP_DISK' => '0',
'NODE_ADDR' => '192.168.0.6',
'VERSION' => '15.08',
'MAX_CPUS_PER_NODE' => 'UNLIMITED',
'REASON' => 'none',
'WEIGHT' => '1',
'TIMESTAMP' => 'Unknown',
'CPU_LOAD' => '0.00',
'SOCKETS' => '2',
'S:C:T' => '2:16:1',
'USER' => 'Unknown',
'NODES' => '1',
'GRES' => '(null)',
'ROOT' => 'no',
'MEMORY' => '257214',
'NODES(A/I/O/T)' => '0/1/0/1',
'AVAIL' => 'up',
'PREEMPT_MODE' => 'OFF',
'THREADS' => '1',
'DEFAULTTIME' => 'n/a',
'CPUS' => '32',
'TIMELIMIT' => 'infinite',
'GROUPS' => 'all',
'JOB_SIZE' => '1-infinite',
'NODELIST' => 'elastic-41',
'HOSTNAMES' => 'nid00005',
'FEATURES' => 'cloud',
'ALLOCNODES' => 'all',
'STATE' => 'idle~',
'FREE_MEM' => '253823',
'PARTITION' => 'Elastic',
'NODES(A/I)' => '0/1',
'PRIORITY' => '1',
'CPUS(A/I/O/T)' => '0/32/0/32',
'CORES' => '16',
'SHARE' => 'NO'
