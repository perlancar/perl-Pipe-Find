package Pipe::Find;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                       find_pipe_processes
                       get_stdin_pipe_process
                       get_stdout_pipe_process
               );

sub find_pipe_processes {
    my $mypid = shift // $$;

    state $pt = do {
        require Proc::ProcessTable;
        Proc::ProcessTable->new;
    };

    my $procs = {};
  FIND:
    {
        my $dh;

        opendir $dh, "/proc/$mypid/fd" or last;
        my %pipes_by_fd;
        my %fds_by_pipe;
        for my $fd (readdir $dh) {
            my $l = readlink "/proc/$mypid/fd/$fd";
            next unless $l && $l =~ /\Apipe:/;
            $pipes_by_fd{$fd} = $l;
            $fds_by_pipe{$l} = $fd;
        }
        last unless keys %pipes_by_fd;
        for my $fd (keys %pipes_by_fd) { $procs->{$fd} = undef }

        opendir $dh, "/proc" or last;
        my @pids = grep {/\A\d+\z/} readdir($dh);

        my %fds_by_pid;
      PID:
        for my $opid (@pids) {
            opendir $dh, "/proc/$opid/fd" or next PID;
            for my $fd (readdir $dh) {
                my $l = readlink "/proc/$opid/fd/$fd";
                next unless $l && $l =~ /\Apipe:/;
                next if $opid == $mypid && $fd == $fds_by_pipe{$l};
                my $fd = $fds_by_pipe{$l} or next;
                $procs->{$fd} = {pid=>$opid};
                $fds_by_pid{$opid} = $fd;
                delete $pipes_by_fd{$fd};
            }
            last PID unless keys %pipes_by_fd;
        }

        my $table = $pt->table;
      TABLE:
        for my $procinfo (@{ $table }) {
            if (defined( my $fd = $fds_by_pid{ $procinfo->{pid} })) {
                # XXX unbless?
                $procs->{$fd} = $procinfo;
                delete $fds_by_pid{$fd};
                last TABLE unless keys %fds_by_pid;
            }
        }
    }

    $procs;
}

sub get_stdin_pipe_process {
    find_pipe_processes()->{0};
}

sub get_stdout_pipe_process {
    find_pipe_processes()->{1};
}

1;
# ABSTRACT: Find the processes behind the pipes that you open

=head1 SYNOPSIS

 use Pipe::Find qw(find_pipe_processes get_stdout_pipe_process);
 $procs = find_pipe_processes(); # hashref, key=fd, value=process info hash

 if ($res->{0}) {
     say "STDIN is connected to a pipe";
     say "pid=$procs->{0}{pid} cmd=$procs->[0]{cmndline}";
 }
 if ($res->{1}) {
     say "STDOUT is connected to a pipe";
     ...
 }
 if ($res->{3}) {
     say "STDERR is connected to a pipe";
     ...
 }
 # ...


=head1 DESCRIPTION


=head1 FUNCTIONS

None exported by default, but they are exportable.

=head2 find_pipe_processes([ $pid ]) => \%procs

List all processes behind the pipes that your process opens. (You can also find
pipes for another process by passing its PID.)

Currently only works on Linux. Works by listing C</proc/$$/fd> and selecting all
fd's that symlinks to C<pipe:*>. Then it will list all C</proc/*/fd> and find
matching pipes. Finally it will run L<Proc::ProcessTable> to find the process
info.

STDIN pipe is at fd 0, STDOUT pipe at fd 1, STDERR at fd 2.

=head2 get_stdin_pipe_process() => \%procinfo

Basically a shortcut to get the fd 0 only, since this is common. Return undef if
STDIN is not piped.

If you plan on getting process information for both STDIN and STDOUT, it's
better to use C<find_pipe_processes()> than calling this function and
C<get_stdout_pipe_process()>, because the latter will scan twice.

=head2 get_stdout_pipe_process() => \%procinfo

Basically a shortcut to get the fd 1 only, since this is common. Return undef if
STDOUT is not piped.

If you plan on getting process information for both STDIN and STDOUT, it's
better to use C<find_pipe_processes()> than calling this function and
C<get_stdin_pipe_process()>, because the latter will scan twice.


=head1 SEE ALSO

=cut
