package Mail::Thread;

use 5.00503;
use strict;
use vars qw($VERSION);
sub debug (@) { print @_ if $Mail::Thread::debug }

$VERSION = '2.0';

sub new {
    my $self = shift;
    return bless {
        messages => [ @_ ],
        id_table => {},
        rootset  => []
    }, $self;
}

sub _get_hdr {
    my ($class, $msg, $hdr) = @_;
    $msg->head->get($hdr);
}

sub _uniq {
    my %seen;
    return grep { !$seen{$_}++ } @_;
}

sub _references {
    my $class = shift;
    my $msg = shift;
    my @references = ($class->_get_hdr($msg, "References") =~ /<([^>]+)>/g);
    my $foo = $class->_get_hdr($msg,"In-Reply-To");
    $foo =~ s/.*?<([^>]+)>.*/$1/;
    push @references, $foo if $foo =~ /\S+\@\S+/ and $references[-1] ne $foo;
    return _uniq(@references);
}

sub _msgid {
    my ($class, $msg) = @_;
    my $id= $msg->isa("Mail::Message") ? $msg->messageId :
            $class->_get_hdr($msg, "Message-ID");
    $id =~ s/^<([^>]+)>.*/$1/; # We expect this not to have <>s
    return $id;
}

sub rootset { @{$_[0]{rootset}} }

sub _dump {
    for (@_) {
        print "\n$_ (";
        print $_->messageid.") [".$_->subject."] has father ".eval{$_->parent};
        print ", child ".eval{$_->child}." and sibling ".eval{$_->next};
        print "\n";
        for my $tag (qw(parent child next)) {
            die "I am my own $tag!" if (eval "\$_->$tag") eq $_;
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
    $self->_finish();
}

sub _finish { }

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
        $cont= $self->_container_class->new($id);
        $self->{id_table}{$id} = $cont;
    }
    $cont->messageid($id);
    return $cont;

}

sub _container_class { "Mail::Thread::Container" }

sub _setup {
    my $self = shift;

    for my $message (@{$self->{messages}}) {
        debug "\n\nLooking at ".$self->_msgid($message)."\n";
        my $this_container = $self->_get_cont_for_id($self->_msgid($message));
        $this_container->message($message);
        debug "  [".$this_container->subject."]\n----\n";
        my $prev = undef;
        my @refs = $self->_references($message);
        debug " Now looking at its references: @refs\n";
        for my $ref (@refs) {
            my $container = $self->_get_cont_for_id($ref);
            debug "   Looking at reference $ref\n";

            if ($prev ne undef) {
                next if $container == $this_container;
                next if $container->has_descendent($prev);
                $prev->add_child($container);
            }
            $prev = $container;
        }
        if ($prev ne undef) { $prev->add_child($this_container) }
        debug "Done with this message!\n----\n";
        if ($Mail::Thread::debug) {
            _dump( values %{$self->{id_table}} );
        }
    }
}


sub _prune_empties {
    my $cont = shift;
    my $level = shift;
    if ($level > 20) { $Mail::Thread::debug++ || print "Something is probably wrong"; }
    if ($level > 30) { die "Deep recursion in empty pruner"; }
    debug " "x$level;
    debug "Looking at ".$cont->messageid."\n";

    my @new_children;
    for my $ctr ($cont->children) {
        my @L = _prune_empties($ctr, $level+1);
        push @new_children, @L;
        $ctr->remove_child($ctr);
    }

    $cont->add_child($_) for @new_children;
    return () if !$cont->message and !$cont->children;
    my @children = $cont->children;
    if (!$cont->message and @children == 1 and $cont->parent) {
        $cont->remove_child($_) for @children;
        return @children;
    }
    return $cont;
}   

package Mail::Thread::Container;
use Carp qw(carp confess croak cluck);

sub new { my $self = shift; bless { @_ }, $self; }

sub message { $_[0]->{message} = $_[1] if @_ == 2; $_[0]->{message} }
sub child   { $_[0]->{child}   = $_[1] if @_ == 2; $_[0]->{child}   }
sub parent  { $_[0]->{parent}  = $_[1] if @_ == 2; $_[0]->{parent}  }
sub next    { $_[0]->{next}    = $_[1] if @_ == 2; $_[0]->{next}    }
sub messageid { $_[0]->{id}      = $_[1] if @_ == 2; $_[0]->{id}      }
sub subject { eval { $_[0]->message->head->get("Subject") } }

sub add_child {
    my ($self, $child) = @_;
    croak "Cowardly refusing to become my own parent: $self"
        if $self == $child;

    if (grep { $_ == $child} $self->children) {
        # All is potentially correct with the world
        $child->parent($self);
        return;
    }

    $child->parent->remove_child($child) if $child->parent;

    if (!$self->child) {
        $self->child($child);
        $child->parent($self);
        return;
    }

    my $x = $self->child;
    my $last = $x;
    while ($x = $x->next) { $last = $x; }
    $last->next($child);
    $child->parent($self);
}

sub remove_child {
    my ($self, $child) = @_;
    return unless $self->child;
    if ($self->child == $child) {  # First one's easy.
        $self->child($child->next);
        $child->next(undef);
        $child->parent(undef);
        return;
    }

    my $x = $self->child;
    my $prev = $x;
    while ($x = $x->next) {
        if ($x == $child) { 
            $prev->next($x->next); # Unlink x
            $x->parent(undef);     # Deparent it
            return; 
        }
        $prev = $x;
    }
}

sub has_descendent {
    my $self = shift;
    my $child = shift;
    die "Assertion failed: $child" unless eval {$child->isa("Mail::Thread::Container")};
    my $there = 0;
    my %seen;
    $self->recurse_down(sub { $there = 1 if $_[0] == $child });

    return $there;
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

        if ($seen{$self->next}) { $self->next(undef) }
        $do_it_all->($self->next, $callback)  if $self->next;
        if ($seen{$self->child}) { $self->child(undef) }
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

=head2 has_descendent($child)

Returns true if this container has the given container as a child somewhere
beneath it.

=head2 add_child($child)

Add the C<$child> as a child of oneself.

=head2 remove_child($child)

Remove the C<$child> as a child from oneself.

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
