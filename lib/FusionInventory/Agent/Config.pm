package FusionInventory::Agent::Config;

use strict;
use warnings;

use English qw(-no_match_vars);
use File::Spec;
use Getopt::Long;

my $basedir = '';
my $basevardir = '';

if ($OSNAME eq 'MSWin32') {
    $basedir = $ENV{APPDATA}.'/fusioninventory-agent';
    $basevardir = $basedir.'/var/lib/fusioninventory-agent';
} else {
    $basevardir = File::Spec->rel2abs($basedir.'/var/lib/fusioninventory-agent'),
}

my $default = {
    'logger'                  => 'Stderr',
    'logfacility'             => 'LOG_USER',
    'delaytime'               => 3600,
    'backend-collect-timeout' => 180,
    'rpc-port'                => 62354,
    'basevardir'              => $basevardir,
};

sub new {
    my ($class, $params) = @_;

    my $self = {
        VERSION => $FusionInventory::Agent::VERSION
    };
    bless $self, $class;
    $self->loadDefaults();

    if ($OSNAME eq 'MSWin32') {
        $self->loadFromWinRegistry();
    } else {
        $self->loadFromCfgFile();
    }
    $self->loadUserParams($params);

    $self->checkContent();


    return $self;
}

sub loadDefaults {
    my ($self) = @_;

    foreach my $key (keys %$default) {
        $self->{$key} = $default->{$key};
    }
}

sub loadFromWinRegistry {
    my ($self) = @_;

    eval {
        require Encode;
        Encode->import('encode');
        require Win32::TieRegistry;
        Win32::TieRegistry->import(
            Delimiter   => "/",
            ArrayValues => 0
        );
    };
    if ($EVAL_ERROR) {
        print "[error] $EVAL_ERROR";
        return;
    }

    my $machKey = $Win32::TieRegistry::Registry->Open( "LMachine", {Access=>Win32::TieRegistry::KEY_READ(),Delimiter=>"/"} );
    my $settings = $machKey->{"SOFTWARE/FusionInventory-Agent"};

    foreach my $rawKey (keys %$settings) {
        next unless $rawKey =~ /^\/(\S+)/;
        my $key = $1;
        my $val = $settings->{$rawKey};
        # Remove the quotes
        $val =~ s/\s+$//;
        $val =~ s/^'(.*)'$/$1/;
        $val =~ s/^"(.*)"$/$1/;
        $self->{lc($key)} = $val;
    }
}

sub loadFromCfgFile {
    my ($self) = @_;

    $self->{etcdir} = [];

    my $file;

    my $in;
    foreach (@ARGV) {
        if (!$in && /^--conf-file=(.*)/) {
            $file = $1;
            $file =~ s/'(.*)'/$1/;
            $file =~ s/"(.*)"/$1/;
        } elsif (/^--conf-file$/) {
            $in = 1;
        } elsif ($in) {
            $file = $_;
            $in = 0;
        } else {
            $in = 0;
        }
    }

    push (@{$self->{etcdir}}, '/etc/fusioninventory');
    push (@{$self->{etcdir}}, '/usr/local/etc/fusioninventory');
#  push (@{$self->{etcdir}}, $ENV{HOME}.'/.ocsinventory'); # Should I?

    if (!$file || !-f $file) {
        foreach (@{$self->{etcdir}}) {
            $file = $_.'/agent.cfg';
            last if -f $file;
        }
        return unless -f $file;
    }

    my $handle;
    if (!open $handle, '<', $file) {
        warn "Config: Failed to open $file: $ERRNO";
        return;
    }

    $self->{'conf-file'} = $file;

    while (<$handle>) {
        s/#.+//;
        if (/([\w-]+)\s*=\s*(.+)/) {
            my $key = $1;
            my $val = $2;
            # Remove the quotes
            $val =~ s/\s+$//;
            $val =~ s/^'(.*)'$/$1/;
            $val =~ s/^"(.*)"$/$1/;
            $self->{$key} = $val;
        }
    }
    close $handle;
}

sub loadUserParams {
    my ($self, $params) = @_;

    foreach my $key (keys %$params) {
        $self->{$key} = $params->{$key};
    }
}

sub checkContent {
    my ($self) = @_;

    if ($self->{'info'}) {
        print STDERR
            "the parameter --info is deprecated, and had no effect anyway\n";
    }

    if ($self->{'no-socket'}) {
        print STDERR
            "the parameter --no-socket is deprecated, use --no-httpd instead\n";
        $self->{'no-httpd'} = 1;
    }

    if ($self->{'rpc-ip'}) {
        print STDERR
            "the parameter --rpc-ip is deprecated, use " .
            "--httpd-ip instead\n";
        $self->{'httpd-ip'} = $self->{'rpc-ip'};
    }

    if ($self->{'rpc-port'}) {
        print STDERR
            "the parameter --rpc-port is deprecated, use " .
            "--httpd-port instead\n";
        $self->{'httpd-port'} = $self->{'rpc-port'};
    }

    if ($self->{'rpc-trust-localhost'}) {
        print STDERR
            "the parameter --rpc-trust-localhost is deprecated, use " .
            "--httpd-trust-localhost instead\n";
        $self->{'httpd-trust-localhost'} = 1;
    }

    if ($self->{'daemon-no-fork'}) {
        print STDERR
            "the parameter --daemon-no-fork is deprecated, use --daemon " .
            "--no-fork instead\n";
        $self->{daemon} = 1;
        $self->{'no-fork'} = 1;
    }

    # a logfile options implies a file logger backend
    if ($self->{logfile}) {
        $self->{logger} .= ',File';
    }

    # We want only canonical path
    if (!$self->{'share-dir'}) {
        if ($self->{'devlib'}) {
                $self->{'share-dir'} = File::Spec->rel2abs('./share/');
        } else {
            eval { 
                require File::ShareDir;
                $self->{'share-dir'} = File::ShareDir::dist_dir('FusionInventory-Agent');
            };
        }
    } else {
        $self->{'share-dir'} = File::Spec->rel2abs($self->{'share-dir'}) if $self->{'share-dir'};
    }

    $self->{basevardir} = File::Spec->rel2abs($self->{basevardir}) if $self->{basevardir};
    $self->{'conf-file'} = File::Spec->rel2abs($self->{'conf-file'}) if $self->{'conf-file'};
    $self->{'ca-cert-file'} = File::Spec->rel2abs($self->{'ca-cert-file'}) if $self->{'ca-cert-file'};
    $self->{'ca-cert-dir'} = File::Spec->rel2abs($self->{'ca-cert-dir'}) if $self->{'ca-cert-dir'};
    $self->{'logfile'} = File::Spec->rel2abs($self->{'logfile'}) if $self->{'logfile'};
}


1;
