package Mail::Thread;

use 5.00503;
use strict;
use vars qw($VERSION);
sub debug (@) { print @_ if $Mail::Thread::debug }

$VERSION = '1.2';

sub new {
    my $self = shift;
    return bless {
        messages => [ @_ ],
        id_table => {},
        rootset  => []
    }, $self;
}

sub _references {
    my $class = shift;
    my $msg = shift;
    my @references = ($msg->head->get("References") =~ /<([^>]+)>/g);
    my $foo = $msg->head->get("In-Reply-To");
    $foo =~ s/^<([^>]+)>.*/$1/;
    push @references, $foo if $foo and $references[-1] ne $foo;
    return (@references);
}

sub _msgid {
    my ($class, $msg) = @_;
    return $msg->isa("Mail::Message") ? $msg->messageId :
           $msg->head->get("Message-ID");
}

sub rootset { @{$_[0]{rootset}} }

sub _dump {
    for (@_) {
        print "\n$_ (";
        print $_->messageid.") [".$_->subject."] has father ".eval{$_->parent};
        print ", child ".eval{$_->child}." and sibling ".eval{$_->next};
        print "\n";
        for my $tag (qw(parent child next)) {
            die "I am my own tag!" if (eval "\$_->$tag") == $_;
        }
    }
}

sub thread {
    my $self = shift;
    $self->_setup();
    $self->{rootset} = [ grep { !$_->parent } values %{$self->{id_table}} ];
    delete $self->{id_table};
    $self->{rootset} = [ map {_prune_empties($_, 0)} @{$self->{rootset}} ]
        unless $Mail::Thread::noprune;
    #$self->_group_set_bysubject();
}

sub _get_cont_for_id {
    my $self = shift;
    my $id = shift;
    my $cont;
    debug "Looking for a container for $id\n";
    if (exists($self->{id_table}{$id})) {
        $cont = $self->{id_table}{$id};
        debug "  Found an existing container for $id, ", $cont->subject,"\n";
    } else {
        debug "  Creating something new to hold $id\n";
        $cont= Mail::Thread::Container->new();
        $self->{id_table}{$id} = $cont;
    }
    $cont->messageid($id);
    return $cont;

}

sub _setup {
    my $self = shift;

    for my $message (@{$self->{messages}}) {
        debug "\n\nLooking at ".$self->_msgid($message)."\n";
        my $c = $self->_get_cont_for_id($self->_msgid($message));
        $c->message($message);
        debug "  [".$c->subject."]\n----\n";
        my $parent_ref = undef;
        my @refs = $self->_references($message);
        debug " Now looking at its references: @refs\n";
        for my $ref (@refs) {
            my $msg_cont = $self->_get_cont_for_id($ref);
            debug "   Looking at reference $ref\n";

            if ($parent_ref ne undef &&
                (not $msg_cont->parent) &&
                $parent_ref != $msg_cont->parent &&
                !$msg_cont->find_child($parent_ref)) {
                    debug "   Threading:\n";
                    $msg_cont->parent($parent_ref);
                    if ($parent_ref->child) {
                        $msg_cont->next($parent_ref->child);
                    }
                    $parent_ref->child($msg_cont);
                     
                    if ($Mail::Thread::debug) { _dump( values %{$self->{id_table}} ); }

            } else {
            }
            $parent_ref = $msg_cont;
        }
        debug " Done threading references\n\n";

        if ($c->parent) {
            debug "Unlinking this from the old parent\n";
            my ($rest, $prev);
            $rest = $c->parent->child;
            while ($rest) {
                last if $rest == $c;
                $prev = $rest; $rest = $rest->next;
            }

            die "Didn't find $c in ".$c->parent 
                unless $rest;

            if (!$prev) { 
                $c->parent->child($c->next); 
            }
            else { $prev->next($c->next) }

            $c->next(0);
            $c->parent(0);
        }

        if (@refs) { 
            if ($Mail::Thread::debug) { _dump( values %{$self->{id_table}} ); }
            debug " Forcing the addition of a parent\n";
            my $daddy = $self->_get_cont_for_id($refs[-1]);
            $c->parent($daddy);
            my $rest = $daddy->child;
            if (!$rest) {
                debug "  OK, setting parent of ".$c->messageid." to ".$daddy->messageid."\n";
                $daddy->child($c);
            } else {
                debug "  $daddy (".$daddy->messageid. ") already has children\n";
                # But one of them may be me! (but shouldn't be)
                my %seen = ();
                while ($rest->next) {
                    die "Loop in ->next chain!" if $seen{$rest}++;
                    die "Huh?" if $rest == $c;
                    die "Double huh!" if $rest == $rest->next;
                    $rest = $rest->next ;
                }
                debug "  Adding $c onto ".$rest->next;
                $rest->next($c);
           }
            if ($Mail::Thread::debug) { _dump( values %{$self->{id_table}} ); }
           
       }
       debug "Done with this message!\n----\n";
        if ($Mail::Thread::debug) {
            _dump( values %{$self->{id_table}} );
        }
    }
}


sub _prune_empties {
    my $cont = shift;
    my $level = shift;
    
    debug " "x$level;
    debug "Looking at ".$cont->messageid."\n";
    if (!$cont->message and !$cont->child) {
        return ();
    }
    if (!$cont->message and $cont->child) {
        debug " "x$level;
        debug "No message: children are - ".join " ", map {$_->messageid} $cont->children;
        debug "\n";
        return map { _prune_empties($_, $level+1) } $cont->children;
    }

    if ($cont->next) {
        debug " "x$level;
        debug "Vising next\n";
        $cont->next(_prune_empties($cont->next, $level+1));
        $cont->next(0) unless $cont->next;
    }
    if ($cont->child) { 
        debug " "x$level;
        debug "Vising children\n";
        $cont->child(_prune_empties($cont->child, $level+1));
        $cont->child(0) unless $cont->child;
    }
    debug "Returning $cont\n" if $cont->message;
    return $cont if $cont->message;
    debug "Pruning this node\n";
    return ();
}   

package Mail::Thread::Container;

sub new { my $self = shift; bless { @_ }, $self; }

sub message { $_[0]->{message} = $_[1] if defined $_[1]; $_[0]->{message} }
sub child   { $_[0]->{child}   = $_[1] if defined $_[1]; $_[0]->{child}   }
sub parent  { $_[0]->{parent}  = $_[1] if defined $_[1]; $_[0]->{parent}  }
sub next    { $_[0]->{next}    = $_[1] if defined $_[1]; $_[0]->{next}    }
sub messageid { $_[0]->{id}      = $_[1] if defined $_[1]; $_[0]->{id}      }
sub subject { eval { $_[0]->message->head->get("Subject") } }


sub find_child {
    my $self = shift;
    my $child = shift;
    die "Assertion failed: $child" unless eval {$child->isa("Mail::Thread::Container")};
    my $there = 0;
    my %seen;
    $self->recurse_down(sub { $there = 1 if $_[0] == $child });

    return 0;
}

sub children {
    my $self = shift;
    my @children;
    my $visitor = $self->child;
    while ($visitor) { push @children, $visitor; $visitor = $visitor->next;}
    return @children;
}

sub recurse_down {
    my %seen;
    my $do_it_all;
    $do_it_all = sub {
        my $self = shift;
        my $callback = shift;
        $seen{$self}++;
        $callback->($self);

        if ($seen{$self->next}) { $self->next(0) }
        $do_it_all->($self->next, $callback)  if $self->next;
        if ($seen{$self->child}) { $self->child(0) }
        $do_it_all->($self->child, $callback) if $self->child;

    };
    $do_it_all->(@_);
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Mail::Thread - Perl implementation of JWZ's mail threading algorithm

=head1 SYNOPSIS

    use Mail::Thread;
    my $threader = new Mail::Thread (@messages);

    $threader->thread;

    dump_em($_,0) for $threader->rootset;

    sub dump_em {
        my ($self, $level) = @_;
        debug (' \\-> ' x $level);
        if ($self->message) {
            print $self->message->head->get("Subject") , "\n";
        } else {
            print "[ Message $self not available ]\n";
        }
        dump_em($self->child, $level+1) if $self->child;
        dump_em($self->next, $level) if $self->next;
    }

=head1 DESCRIPTION

This module implements something relatively close to Jamie Zawinski's mail
threading algorithm, as described by http://www.jwz.org/doc/threading.html.
Any deviations from the algorithm are accidental.

It doesn't do threading by subject yet, because I don't need it yet.

It's happy to be handed C<Mail::Internet> and C<Mail::Box::Message> objects,
since they're more or less the same, but nothing other than that.

=head1 METHODS

=head2 new(@messages)

Creates a new threader; requires a bunch of messages to thread.

=head2 thread

Goes away and threads the messages together.

=head2 rootset

Returns a list of C<Mail::Thread::Container>s which are not the parents
of any other message.

=head1 C<Mail::Thread::Container> methods

C<Mail::Thread::Container>s are the nodes of the thread tree. You can't just
have the ordinary messages, because we might not have the message in question.
For instance, a mailbox could contain two replies to a question that we
haven't received yet. So all "logical" messages are stuffed in containers,
whether we happen to have that container or not.

To do anything useful with the thread tree, you're going to have to recurse
around the list of C<Mail::Thread::Containers>. You do this with the following
methods:

=head2 parent

=head2 child

=head2 next

Returns the container which is the parent, child or immediate sibling
of this one, if one exists.

=head2 message

Returns the message held in this container, if we have one.

=head2 id

Returns the message ID for this container. This will be around whether we
have the message or not, since some other message will have referred to it
by message ID.

=head2 find_child($child)

Returns true if this container has the given container as a child somewhere
beneath it.

=head2 children

Returns a list of the B<immediate> children of this container.

=head2 recurse_down($callback)

Calls the given callback on this node and B<all> of its children.

=head1 AUTHOR

Simon Cozens, E<lt>simon@kasei.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Kasei

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
