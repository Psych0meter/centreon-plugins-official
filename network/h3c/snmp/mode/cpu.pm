#
# Copyright 2018 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package network::h3c::snmp::mode::cpu;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::values;
use centreon::plugins::statefile;

my $oid_entPhysicalEntry = '.1.3.6.1.2.1.47.1.1.1.1';
my $oid_entPhysicalDescr = '.1.3.6.1.2.1.47.1.1.1.1.2';
my $oid_entPhysicalContainedIn = '.1.3.6.1.2.1.47.1.1.1.1.4';
my $oid_entPhysicalClass = '.1.3.6.1.2.1.47.1.1.1.1.5';
my $oid_entPhysicalName = '.1.3.6.1.2.1.47.1.1.1.1.7';

my $maps_counters = {
    cpu => { 
        '000_usage'   => { set => {
                        key_values => [ { name => 'EntityExtCpuUsage' }, { name => 'num' }, ],
                        output_template => ' : %.2f %%',
                        perfdatas => [
                            { label => 'cpu', value => 'EntityExtCpuUsage_absolute', template => '%.2f',
                              min => 0, max => 100, unit => '%', label_extra_instance => 1, instance_use => 'num_absolute' },
                        ],
                    }
               },
        },
};

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "reload-cache-time:s"     => { name => 'reload_cache_time', default => 180 },
                                  "display-entity-name"     => { name => 'display_entity_name' },
                                });                         

    foreach my $key (('cpu')) {
        foreach (keys %{$maps_counters->{$key}}) {
            my ($id, $name) = split /_/;
            if (!defined($maps_counters->{$key}->{$_}->{threshold}) || $maps_counters->{$key}->{$_}->{threshold} != 0) {
                $options{options}->add_options(arguments => {
                                                            'warning-' . $name . ':s'    => { name => 'warning-' . $name },
                                                            'critical-' . $name . ':s'    => { name => 'critical-' . $name },
                                               });
            }
            $maps_counters->{$key}->{$_}->{obj} = centreon::plugins::values->new(output => $self->{output}, perfdata => $self->{perfdata},
                                                      label => $name);
            $maps_counters->{$key}->{$_}->{obj}->set(%{$maps_counters->{$key}->{$_}->{set}});
        }
    }
    
    $self->{statefile_cache} = centreon::plugins::statefile->new(%options);

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
    
    foreach my $key (('cpu')) {
        foreach (keys %{$maps_counters->{$key}}) {
            $maps_counters->{$key}->{$_}->{obj}->init(option_results => $self->{option_results});
        }
    }
    
    $self->{statefile_cache}->check_options(%options);
}

sub run {
    my ($self, %options) = @_;
    $self->{snmp} = $options{snmp};
    
    $self->manage_selection();
    
    my $multiple = 1;
    if (scalar(keys %{$self->{cpu}}) == 1) {
        $multiple = 0;
    }
    
    if ($multiple == 1) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => 'All CPU usages are ok');
    }
    
    foreach my $id (sort keys %{$self->{cpu}}) {     
        my ($short_msg, $short_msg_append, $long_msg, $long_msg_append) = ('', '', '', '');
        my @exits = ();
        foreach (sort keys %{$maps_counters->{cpu}}) {
            my $obj = $maps_counters->{cpu}->{$_}->{obj};
            $obj->set(instance => $id);
        
            my ($value_check) = $obj->execute(values => $self->{cpu}->{$id});

            if ($value_check != 0) {
                $long_msg .= $long_msg_append . $obj->output_error();
                $long_msg_append = ', ';
                next;
            }
            my $exit2 = $obj->threshold_check();
            push @exits, $exit2;

            my $output = $obj->output();
            $long_msg .= $long_msg_append . $output;
            $long_msg_append = ', ';
            
            if (!$self->{output}->is_status(litteral => 1, value => $exit2, compare => 'ok')) {
                $short_msg .= $short_msg_append . $output;
                $short_msg_append = ', ';
            }
            
            $maps_counters->{cpu}->{$_}->{obj}->perfdata(extra_instance => $multiple);
        }

        $self->{output}->output_add(long_msg => "CPU '" . $self->{cpu}->{$id}->{num} . "' Usage $long_msg [entity = '" . $self->{cpu}->{$id}->{name} . "']");
        my $exit = $self->{output}->get_most_critical(status => [ @exits ]);
        if (!$self->{output}->is_status(litteral => 1, value => $exit, compare => 'ok')) {
            $self->{output}->output_add(severity => $exit,
                                        short_msg => "CPU '" . $self->{cpu}->{$id}->{num} . "' Usage $short_msg"
                                        );
        }
        
        if ($multiple == 0) {
            $self->{output}->output_add(short_msg => "CPU '" . $self->{cpu}->{$id}->{num} . "' Usage $long_msg");
        }
    }
     
    $self->{output}->display();
    $self->{output}->exit();
}

sub check_cache {
    my ($self, %options) = @_;

    $self->{hostname} = $self->{snmp}->get_hostname();
    $self->{snmp_port} = $self->{snmp}->get_port();
    
    # init cache file
    $self->{write_cache} = 0;
    my $has_cache_file = $self->{statefile_cache}->read(statefile => 'cache_h3c_entity_' . $self->{hostname}  . '_' . $self->{snmp_port});
    my $timestamp_cache = $self->{statefile_cache}->get(name => 'last_timestamp');
    if ($has_cache_file == 0 ||
        !defined($timestamp_cache) || ((time() - $timestamp_cache) > (($self->{option_results}->{reload_cache_time}) * 60))) {
        push @{$self->{snmp_request}}, { oid => $oid_entPhysicalEntry, start => $oid_entPhysicalDescr, end => $oid_entPhysicalName };
        $self->{write_cache} = 1;
    }
}

sub write_cache {
    my ($self, %options) = @_;
    
    if ($self->{write_cache} == 1) {
        my $datas = {};
        $datas->{last_timestamp} = time();
        $datas->{oids} = $self->{results}->{$oid_entPhysicalEntry};
        $self->{statefile_cache}->write(data => $datas);
    } else {
        $self->{results}->{$oid_entPhysicalEntry} = $self->{statefile_cache}->get(name => 'oids');
    }
}

sub get_long_name {
    my ($self, %options) = @_;
    
    my @names = ($self->{results}->{$oid_entPhysicalEntry}->{$oid_entPhysicalDescr . '.' . $options{instance}});
    my %loop = ($options{instance} => 1);
    my $child = $self->{results}->{$oid_entPhysicalEntry}->{$oid_entPhysicalContainedIn . '.' . $options{instance}};
    while (1) {
        last if (!defined($child) || defined($loop{$child}) || !defined($self->{results}->{$oid_entPhysicalEntry}->{$oid_entPhysicalDescr . '.' . $child}));
        
        unshift @names, $self->{results}->{$oid_entPhysicalEntry}->{$oid_entPhysicalDescr . '.' . $child};
        $loop{$child} = 1;
        $child = $self->{results}->{$oid_entPhysicalEntry}->{$oid_entPhysicalContainedIn . '.' . $child};
    }
    
    return join(' > ', @names);
}

sub manage_selection {
    my ($self, %options) = @_;

    my $oid_h3cEntityExtCpuUsage = '.1.3.6.1.4.1.2011.10.2.6.1.1.1.1.6';
    my $oid_hh3cEntityExtCpuUsage = '.1.3.6.1.4.1.25506.2.6.1.1.1.1.6';
    $self->{snmp_request} = [ 
        { oid => $oid_h3cEntityExtCpuUsage },
        { oid => $oid_hh3cEntityExtCpuUsage },
    ];
    $self->check_cache() if (defined($self->{option_results}->{display_entity_name}));

    $self->{results} = $self->{snmp}->get_multiple_table(oids => $self->{snmp_request},
                                                         nothing_quit => 1);
    $self->write_cache() if (defined($self->{option_results}->{display_entity_name}));
    $self->{branch} = $oid_hh3cEntityExtCpuUsage;
    if (defined($self->{results}->{$oid_h3cEntityExtCpuUsage}) && scalar(keys %{$self->{results}->{$oid_h3cEntityExtCpuUsage}}) > 0) {
        $self->{branch} = $oid_h3cEntityExtCpuUsage;
    }
    
    my $mapping = {
        EntityExtCpuUsage => { oid => $self->{branch} },
    };
    
    $self->{cpu} = {};
    foreach my $oid (keys %{$self->{results}->{$self->{branch}}}) {
        $oid =~ /^$mapping->{EntityExtCpuUsage}->{oid}\.(.*)$/;
        my $instance = $1;
        my $result = $self->{snmp}->map_instance(mapping => $mapping, results => $self->{results}->{$self->{branch}}, instance => $instance);
        
        if (defined($result->{EntityExtCpuUsage}) && $result->{EntityExtCpuUsage} > 0) {
            my $name = '-';
            
            if (defined($self->{option_results}->{display_entity_name})) {
                $name = $self->get_long_name(instance => $instance);
            }
            $self->{cpu}->{$instance} = { num => $instance, name => $name, %$result};
        }
    }
    
    if (scalar(keys %{$self->{cpu}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No entry found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check CPU usages.

=over 8

=item B<--warning-usage>

Threshold warning.

=item B<--critical-usage>

Threshold critical.

=item B<--reload-cache-time>

Time in seconds before reloading cache file (default: 180).

=item B<--display-entity-name>

Display entity name of the component. A cache file will be used.

=back

=cut
