BEGIN { eval "use Mail::Box::Manager;"; 
    if ($@) { require Test::More; Test::More->import(skip_all =>
        "You don't have Mail::Box::Manager"); exit; }
}

use Test::More tests => 3;
use_ok("Mail::Thread");
my $mgr = new Mail::Box::Manager;
my $box = $mgr->open(folder => "t/testbox-4");

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
            'Re: Working Group Proposal',
            'F122YsoaJ70EgyBiQhe00003799@hotmail.com'
          ],
          [
            0,
            'Working Group Proposal',
            '20000719155037.A27886@O2.chapin.edu'
          ],
          [
            1,
            'Re: Working Group Proposal',
            '20000719161418.D17718@ghostwheel.wks.na.deuba.com'
          ],
          [
            1,
            'Re: Working Group Proposal',
            '87em4pa0ec.fsf@fire-swamp.org'
          ],
          [
            2,
            'Re: Working Group Proposal',
            '20000719154851.C5309@cbi.tamucc.edu'
          ],
          [
            3,
            'Re: Working Group Proposal',
            '20000719164529.E17718@ghostwheel.wks.na.deuba.com'
          ],
          [
            4,
            'Re: Working Group Proposal',
            '20000719160141.D5309@cbi.tamucc.edu'
          ]
        ]
 );
