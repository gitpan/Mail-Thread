BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 3;
use_ok("Mail::Thread");
my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox-3");

my $threader = new Mail::Thread($box->messages);

$threader->thread;

is($threader->rootset, 2, "We have two main threads");

my @stuff;
for ($threader->rootset) {
    dump_em($_, 0);
}

sub dump_em {
    my ($self, $level) = @_;
    push @stuff, 
    [ $level, eval { "".$self->message->head->get("Subject") }, $self->{id}
             || "[ Message not available ]" ];
    dump_em($self->next, $level) if $self->next;
    dump_em($self->child, $level+1) if $self->child;
}

is_deeply(\@stuff,
[
          [
            0,
            'Re: Zip/Postal codes.',
            '3E146C15.8000302@ntlworld.com'
          ],
          [
            1,
            'Re: Zip/Postal codes.',
            '20030102180231.F635@hermione.osp.nl'
          ],
          [
            0,
            'Re: Zip/Postal codes.',
            '20030102115117.A21351@cs839290-a.mtth.phub.net.cable.rogers.com'
          ]
        ]
 );
