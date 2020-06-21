# klaus.wich@axiros.com
#
# generate xml description for AXIROS AXESS from given data model
#
# Version 1.0. January 2012:
#           - first version
# Version 1.1. July 2013:
#           - recognize and handle service models correctly
# Version 1.2. January 2015:
#           - add datamodel information to XML
#           - detect service definitions correctly
# Version 1.3. June 2015:
#           - XML escape and trim description strings
# Version 1.4. December 2015:
#           - Create comma separated lists as strings
# Version 1.4.1 December 2015:
#           - Escape Quotes and carriage returns in def
#           - Tidy descriptions
#           - prevent dublicate descriptions
# Version 1.4.2 January 2016:
#           - Generate writeonly parameters with option "emptyfromcpe" if they end on
#             password, passphrase, key, secret, pin


package axiros;

use strict;
use File::Basename;
use Data::Dumper;

#$Data::Dumper::Maxdepth = 3;

my $VERSION = "1.4.2";
my $YEAR    = "2016";

my $gInd = 2;
my $gIndTab = 4;

my @ids = (0,0,0,0,0,0,0,0,0,0,0,0,0);
my $MAXID = 12;
my %DataTypesTable;
my $ServiceModel = 0;

# list of endings used for "emptyformcpe":
my @CMDKEYS=(["password", 8], ["passphrase", 10], ["key", 3], ["secret", 6], ["pin" , 3]);


# set to 1 to enable debug output
my $DBG=0;

sub indprint
{
    printf("% ${_[0]}s%s\n", "",$_[1]);
}

sub DBG
{
    printf("DBG >%s:%s<\n", $_[0], $_[1]);
}


sub resetid
{
    my ($lev) = @_;
    for (my $i= $lev+1; $i < $MAXID; $i++)
    {
        $ids[$i] = 0;
    }
}

sub printheader
{
    my ($source, $model) = @_;

    my $s = "<!--\n".
    "   AXESS Data model definitions for\n\n".
    "             %s\n\n".
    "   defined in : %s\n".
    "   generated  : %s  (G-$VERSION)\n".
    " \n".
    "   Copyright Axiros GmbH 2012 - $YEAR, All rights reserved\n".
    " -->\n";
    printf($s, $model, basename($source), (scalar localtime));
}

# Process whitespace (from report.pl)
sub html_whitespace
{
    my ($inval) = @_;

    return $inval unless $inval;

    # remove any leading whitespace up to and including the first line break
    $inval =~ s/^[ \t]*\n//;

    # remove any trailing whitespace (necessary to avoid polluting the prefix
    # length)
    $inval =~ s/\s*$//;

    # determine longest common whitespace prefix
    my $len = undef;
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        # ignore lines consisting only of whitespace (they never make any
        # difference)
        next if $line =~ /^\s*$/;
        my ($pre) = $line =~ /^(\s*)/;
        $len = length($pre) if !defined($len) || length($pre) < $len;
        if ($line =~ /\t/) {
            my $tline = $line;
            $tline =~ s/\t/\\t/g;
        }
    }
    $len = 0 unless defined $len;

    # remove it
    my $outval = '';
    foreach my $line (@lines) {
        next if $line =~ /^\s*$/;
        $line = substr($line, $len);
        $outval .= $line . "\n";
    }

    # remove trailing newline
    chomp $outval;
    return $outval;
}

sub get_history_description
{
    my ($history) = @_;

    return undef unless $history && @$history;
    my $old = '';
    foreach my $item (reverse @$history) {
        my $descact = $item->{descact};
        my $new = $item->{description};
        $new = html_whitespace($new);
        if ($descact eq 'prefix')
        {
            $new = $new . (($old ne '' && $new ne '') ? "\n" : "") . $old;
        }
        elsif ($descact eq 'append')
        {
            my $sep = $new =~ /^[ \t]*\{\{(enum|pattern)/ ? "  " : "\n";
            $old .= (($old ne '' && $new ne '') ? $sep : "") . $new;
        }
        else
        {
            $old = $new;
        }
    }
    return $old;
}


sub get_node_type
{
    my ($node) = @_;

    return undef unless $node;

    my $type = $node->{type};
    if ($node->{syntax})
    {
        my $syntax = $node->{syntax};
        # check if list:
        if ($syntax->{list} == 1)
        {
            $type = "list";
        }
        else
        {
            if ($syntax->{ref})
            {
                $type = $syntax->{ref};
            }
            elsif ($syntax->{base})
            {
                $type = $syntax->{base};
            }
         }
    }
    return $type;
}

sub getdescription
{
    my ($node) = @_;

    my $des = $node->{description};
    my $descact = $node->{descact};
    my $old = "";

    my $old = get_history_description($node->{history});
    # update action
    $descact = defined $old ? 'replace' : 'create' unless $descact;
    $old = '' unless defined $old;
    if ($descact eq 'replace' && length($des) > length($old) &&
        substr($des, 0, length($old)) eq $old &&
        substr($des, length($old), 1) eq "\n") {
        $des = substr($des, length($old));
        $des =~ s/^\s+//;
        $descact = 'append';
    }
    if ($descact eq 'prefix')
    {
        $des = $des . (($old ne '' && $des ne '') ? "\n" : "") . $old;
    }
    elsif ($descact eq 'append')
    {
        my $sep = $des =~ /^[ \t]*\{\{(enum|pattern)/ ? "  " : "\n";
        $des = $old . (($old ne '' && $des ne '') ? $sep : "") . $des;
    }

    if ($des =~ /\{\{datatype\|expand\}\}/)
    {
        my $typdes = $DataTypesTable{get_node_type($node)}{description};
        if ($typdes)
        {
            $des =~ s/\{\{datatype\|expand\}\}/$typdes/;
        }
    }

    if ($des =~ /\{\{enum\}\}/)
    {
        my $enum = join("', '",keys %{$node->{values}});
        $des =~ s/\{\{enum\}\}/'$enum'./;
    }

    if ($des =~ /\{\{units\}\}/)
    {
        $des =~ s/\{\{units\}\}/$node->{units}/g;
    }

    if ($des =~ /\{\{numentries\}\}/)
    {
        # TODO add check for table, if somebody complains
        my $name = $node->{name};
        $name =~ s/NumberOfEntries//;
        $des =~ s/\{\{numentries\}\}/The number of entries in the '$name' table/;
    }

    $des =~ s/\{\{(noreference|reference)\}\}//g;
    $des =~ s/\{\{reference\|(.)/$1/g;
    $des =~ s/\{\{(true|false)\}\}/'$1'/g;
    $des =~ s/[\n\r\t<>]+/ /g;
    $des =~ s/["]+/ /g;
    # work with sloppy description strings:
    # - unescape XML characters, if there are any (has to be done to prevent double escaping)
    $des =~ s/&amp;/&/g;
    $des =~ s/&lt;/</g;
    $des =~ s/&gt;/>/g;
    # - escape XML characters
    $des =~ s/&/&amp;/g;
    $des =~ s/</&lt;/g;
    $des =~ s/>/&gt;/g;
    #trim
    $des =~ s/^\s+|\s+$//g;
    #reduce space
    $des =~ s/ +/ /g;
    # tidy it up
    $des =~ s/\{\{enum\|([^|}]+?)\|[^}]+?\}\}/'$1'/g;
    $des =~ s/\{\{enum\|(.+?)\}\}/'$1'/g;
    $des =~ s/\{\{param\|(.+?)\}\}/'$1'/g;
    $des =~ s/\{\{object\|##\.([^|]+?)\}\}/'$1' object/g;
    $des =~ s/\{\{object\|#\.([^|]+?)\}\}/'$1' object/g;
    $des =~ s/\{\{object\|\|([^|]+?)\}\}/'$1' object/g;
    $des =~ s/\{\{object\|([^|]+?)\}\}/'$1' object/g;
    $des =~ s/\{\{param\}\}/this parameter/g;
    $des =~ s/\{\{object\}\}/object/g;
    $des =~ s/\{\{empty\}\}|\{\{null\}\}/empty/g;
    $des =~ s/\{\{bibref\|(.+?)\}\}/[ref:$1]/g;
    $des =~ s/\{\{enum\}\}//g;
    $des =~ s/\{\{hidden\}\}//g;
    $des =~ s/\{\{list\}\}/Comma separated list./g;
    $des =~ s/\{\{list\|/Comma separated list /g;
    $des =~ s/\{\{pattern\}\}/Defined as pattern./g;
    $des =~ s/\{\{nopattern\}\}//g;
    $des =~ s/\{\{pattern\|(.+?)\}\}/Pattern '$1'/g;
    $des =~ s/\{\{command\}\}/The value of this parameter is not part of the device configuration and is always 'false' when read./g;

    # clean the remianing stuff, left overs from the previous replacements ...
    $des =~ s/\}\}//g;

    return $des;
}



sub axiros_node
{
    my ($node, $ind) = @_;

    #create type table:
    if ($ind == 0)
    {
        foreach my $dtype (@{$node->{dataTypes}})
        {
            my $type = ($dtype->{base} ne "") ? $dtype->{base} : $dtype->{prim};
            # get size:
            my $tsize = 0;
            my $syn = $dtype->{syntax};
            foreach my $size (@{$syn->{sizes}})
            {
                $size->{maxLength} and $tsize = $size->{maxLength};
            }
            #check if derived type:
            if ($DataTypesTable{$type})
            {
                $tsize == 0 and $tsize = $DataTypesTable{$type}{size};
                $type = $DataTypesTable{$type}{type};
            }
            $DataTypesTable{$dtype->{name}}{type}=$type;
            $DataTypesTable{$dtype->{name}}{description}=$dtype->{description};
            $tsize > 0 and $DataTypesTable{$dtype->{name}}{size}=$tsize;
        }

        #print Dumper(%DataTypesTable);
    }

    if ($ind == 1 ) # get prefix
    {
        printheader($ARGV[0], $node->{name});
        #DBG($ind, $node->{name});
        if (index($node->{name}, "InternetGatewayDevice" ) == -1 &&
            index($node->{name}, "Device" ) == -1)
        {
            $ServiceModel = 1;
            $gInd = 1;
            # Add Service Definition:
            print "  <Services>\n";
        }
    }

    #process nodes
    if ($ind > $gInd)
    {
        $ind = ($ind - $gInd);
        my $i = $ind * $gIndTab;
        print "\n";
        $ids[$ind] += 1;
        if ($node->{type} ne "object")
        {
            indprint($i,"<!--PARAM: $node->{path}-->");
            my $des = getdescription($node);
            indprint($i, "<$node->{name}");
            indprint($i, "   TR_description=\"$des\"");

            $des = $node->{path};
            $des =~ s/Device\./InternetGatewayDevice\./;
            $des =~ s/\{i\}\.//;
            indprint($i, "   description=\"$des\"");
            my $type = $node->{type};
            my $tsize = "";
            if ($node->{syntax})
            {
                my $syntax = $node->{syntax};
                # check if list:
                if ($syntax->{list} == 1)
                {
                    $type = "list";
                }
                else
                {
                    if ($syntax->{ref})
                    {
                        $type = $syntax->{ref};
                    }
                    elsif ($syntax->{base})
                    {
                        $type = $syntax->{base};
                    }
                    #get length if defined
                    if ($node->{syntax}->{sizes})
                    {
                        foreach my $size (@{$node->{syntax}->{sizes}})
                        {
                            $size->{maxLength} and $tsize=sprintf("(%d)",$size->{maxLength});
                        }
                    }
                }
                # check if writeonly
                if ($node->{syntax}->{hidden} || $node->{syntax}->{command})
                {
                    my $n = lc $node->{path};
                    my $notfound = 1;
                    for (my $k=0; $k < @CMDKEYS; $k++)
                    {
                       if (substr($n, -$CMDKEYS[$k][1]) eq  $CMDKEYS[$k][0])
                       {
                            indprint($i, "   emptyfromcpe=\"1\"");
                            print STDERR "Set emptyfromcpe for $node->{path}\n";
                            $notfound = 0;
                       }
                    }
                    if ($notfound)
                    {
                            print STDERR "NOSET            for $node->{path}\n";
                    }
                }
            }

            # check if derived type
            $DBG and indprint($i, "   DBGtype=\"$type\"");
            my $otype;
            if ($DataTypesTable{$type})
            {
                if ($DataTypesTable{$type} ne "")
                {
                    $otype = $type;
                    $tsize eq "" and $tsize = $DataTypesTable{$type}{size};
                    $type = $DataTypesTable{$type}{type};
                }
            }
            indprint($i, "   type=\"$type\"");
            indprint($i, "   typeLength=\"$tsize\"");

            my $rw = ($node->{access} eq "readWrite") ? "W" : "-";
            indprint($i, "   write=\"$rw\"");
            my $def = "-";
            if ($node->{default} )
            {
                $def = ($node->{default} ne "") ? $node->{default} : "-";
                # Check for special characters and replace:
                $def =~ s/"/&quot;/g;
                $def =~ s/\n/&#10;/g;
                $def =~ s/\r/&#13;/g;
            }
            indprint($i, "   default=\"$def\"");
            my $majorVer = $node->{majorVersion} ? $node->{majorVersion} : "0";
            my $minVer = $node->{minorVersion} ? $node->{minorVersion} : "0";
            indprint($i, "   version=\"$majorVer.$minVer\"");
            indprint($i, "   id=\"$ids[$ind]\"");
            indprint($i, "/>");
            $DBG and indprint($i, "<!--INF:type=\"$type\" was derived from def type \"$otype\" -->");
        }
        else
        {
            indprint($i,"<!--OBJECT: $node->{path}-->");
            my $name = $node->{name};
            my $islist = $name =~ /.+{i}/ ? "true" : "false";
            $name =~ s /\..*//g;
            indprint($i, "<$name id=\"$ids[$ind]\" islist=\"$islist\">");
        }
    }
}



sub axiros_init
{
    @ids = (0,0,0,0,0,0,0,0,0,0,0,0,0);
    $DataTypesTable{list}{type}="string";
    print "<?xml version=\"1.0\"?>\n<InternetGatewayDevice id=\"1\" islist=\"false\">\n";
}


sub axiros_postpar
{
    my ($node, $ind) = @_;
    if ($ind > $gInd)
    {
        $ind = ($ind - $gInd-1);
        my $i = $ind * $gIndTab;
    }
}


sub axiros_post
{
    my ($node, $ind) = @_;
    if ($ind > $gInd)
    {
        $ind = ($ind - $gInd);
        my $i = $ind * $gIndTab;
        if ($node->{type} eq "object")
        {
            my $name = $node->{name};
            $name =~ s /\..*//g;
            indprint($i, "</$name>");
            indprint($i, "<!--OBJECT END: $node->{path}-->");
            resetid($ind);
        }
    }
}


sub axiros_end
{
    if ($ServiceModel == 1)
    {
        print "  </Services>\n";
    }
    print "</InternetGatewayDevice>"
}


1;
