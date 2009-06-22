package SBEAMS::PeptideAtlas::ProtInfo;

###############################################################################
# Class       : SBEAMS::PeptideAtlas::ProtInfo
# Author      : Terry Farrah <tfarrah@systemsbiology.org>
#
=head1 SBEAMS::PeptideAtlas::ProtInfo

=head2 SYNOPSIS

  SBEAMS::PeptideAtlas::ProtInfo

=head2 DESCRIPTION

This is part of the SBEAMS::PeptideAtlas module which handles
things related to PeptideAtlas protein identifications.

=cut
#
###############################################################################

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw();
$VERSION = q[$Id$];
@EXPORT_OK = qw();

use SBEAMS::Connection;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::Settings;
use SBEAMS::PeptideAtlas::Tables;


###############################################################################
# Global variables
###############################################################################
use vars qw($VERBOSE $TESTONLY $sbeams);
our @EXPORT = qw(get_preferred_protid_from_list);


###############################################################################
# Constructor
###############################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    $VERBOSE = 0;
    $TESTONLY = 0;
    return($self);
} # end new


###############################################################################
# setSBEAMS: Receive the main SBEAMS object
###############################################################################
sub setSBEAMS {
    my $self = shift;
    $sbeams = shift;
    return($sbeams);
} # end setSBEAMS



###############################################################################
# getSBEAMS: Provide the main SBEAMS object
###############################################################################
sub getSBEAMS {
    my $self = shift;
    return $sbeams || SBEAMS::Connection->new();
} # end getSBEAMS



###############################################################################
# setTESTONLY: Set the current test mode
###############################################################################
sub setTESTONLY {
    my $self = shift;
    $TESTONLY = shift;
    return($TESTONLY);
} # end setTESTONLY



###############################################################################
# setVERBOSE: Set the verbosity level
###############################################################################
sub setVERBOSE {
    my $self = shift;
    $VERBOSE = shift;
    return($VERBOSE);
} # end setVERBOSE



###############################################################################
# loadBuildProtInfo -- Loads all protein identification info for build
###############################################################################
sub loadBuildProtInfo {
  my $METHOD = 'loadBuildProtInfo';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $atlas_build_directory = $args{atlas_build_directory}
    or die("ERROR[$METHOD]: Parameter atlas_build_directory not passed");


  #### Find and open files.
  my $ident_file = "$atlas_build_directory/".
    "PeptideAtlasInput.PAprotIdentlist";
  my $relation_file = "$atlas_build_directory/".
    "PeptideAtlasInput.PAprotRelationships";

  unless (open(IDENTFILE,$ident_file)) {
    print "ERROR: Unable to open for read file '$ident_file'\n";
    return;
  }
  unless (open(RELFILE,$relation_file)) {
    print "ERROR: Unable to open for read file '$relation_file'\n";
    return;
  }


  #### Loop through all protein identifications and load

  my $unmapped = 0;
  my $unmapped_represented_by = 0;
  my $loaded = 0;
  my $already_in_db = 0;
  my $nan_count = 0;

  # Input is PA.protIdentlist file
  # Process one line at a time
  while (my $line = <IDENTFILE>) {
    chomp ($line);
    my ($protein_group_number,
	$biosequence_name,
	$probability,
	$confidence,
	$level_name,
	$represented_by_biosequence_name) = split(",", $line);

    # very early atlas builds abbreviated this
    if ($level_name eq "possibly_disting") {
      $level_name = "possibly_distinguished";
    }

    # I don't know what to do with nan. Let's set it to zero.
    if ($probability eq "nan") {
      $nan_count++;
      $probability = "0.0";
    }
    if ($confidence eq "nan") {
      $nan_count++;
      $confidence = "0.0";
    }

    # skip UNMAPPED proteins.
    if ($biosequence_name =~ /UNMAPPED/) {
      $unmapped++;
      next;
    }
    if ($represented_by_biosequence_name =~ /UNMAPPED/) {
      $unmapped_represented_by++;
      next;
    }

    my $inserted = $self->insertProteinIdentification(
       atlas_build_id => $atlas_build_id,
       biosequence_name => $biosequence_name,
       protein_group_number => $protein_group_number,
       level_name => $level_name,
       represented_by_biosequence_name => $represented_by_biosequence_name,
       probability => $probability,
       confidence => $confidence,
    );

    if ($inserted) {
      $loaded++;
    } else {
      $already_in_db++;
    }
  }

  if ($VERBOSE) {
    print "$loaded entries loaded into protein_identification table.\n";
    print "$already_in_db protIDs were already in table so not loaded.\n";
    print "$unmapped UNMAPPED entries ignored.\n";
    print "$unmapped_represented_by entries with UNMAPPED represented_by".
	   " identifiers ignored.\n";
    if ($nan_count) {
      print "$nan_count probability/confidence values of nan set to 0.0.\n";
    }
  }

  #### Loop through all protein relationships and load

  $loaded = 0;
  $already_in_db = 0;

  # Input is PA.protRelationships file
  # Process one line at a time
  while (my $line = <RELFILE>) {
    chomp ($line);
    my ($reference_biosequence_name,
	$related_biosequence_name,
	$relationship_name,
	) = split(",", $line);

    my $inserted = $self->insertBiosequenceRelationship(
       atlas_build_id => $atlas_build_id,
       reference_biosequence_name => $reference_biosequence_name,
       related_biosequence_name => $related_biosequence_name,
       relationship_name => $relationship_name,
    );

    if ($inserted) {
      $loaded++;
    } else {
      $already_in_db++;
    }
  }

  if ($VERBOSE) {
    print "$loaded entries loaded into biosequence_relationship table.\n";
    print "$already_in_db relationships were already in table so not loaded.\n";
  }

} # end loadBuildProtInfo



###############################################################################
# insertProteinIdentification --
###############################################################################
sub insertProteinIdentification {
  my $METHOD = 'insertProteinIdentification';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");
  my $biosequence_name = $args{biosequence_name}
    or die("ERROR[$METHOD]: Parameter biosequence_name not passed");
  my $protein_group_number = $args{protein_group_number}
    or die("ERROR[$METHOD]: Parameter protein_group_number not passed");
  my $level_name = $args{level_name}
    or die("ERROR[$METHOD]: Parameter level_name not passed");
  my $represented_by_biosequence_name =
          $args{represented_by_biosequence_name}
    or die("ERROR[$METHOD]: Parameter represented_by_biosequence_name ".
          "not passed");
  my $probability = $args{probability}
    or die("ERROR[$METHOD]: Parameter probability not passed");
  my $confidence = $args{confidence}
    or die("ERROR[$METHOD]: Parameter confidence not passed");

  our $counter;

  #### Get the biosequence_ids
  my $biosequence_id = $self->get_biosequence_id(
    biosequence_name => $biosequence_name,
    atlas_build_id => $atlas_build_id,
  );
  my $represented_by_biosequence_id = $self->get_biosequence_id(
    biosequence_name => $represented_by_biosequence_name,
    atlas_build_id => $atlas_build_id,
  );


  #### Get the presence_level_id
  my $presence_level_id = $self->get_presence_level_id(
    level_name => $level_name,
  );


  #### Check to see if this protein_identification is in the database
  my $protein_identification_id = $self->get_protein_identification_id(
    biosequence_id => $biosequence_id,
    atlas_build_id => $atlas_build_id,
  );


  #### If not, INSERT it
  if ($protein_identification_id) {
    if ($VERBOSE) {
      print STDERR "WARNING: Identification info for $biosequence_name".
                 " ($biosequence_id) already in database\n";
    }
    return ('');
  } else {
    $protein_identification_id = $self->insertProteinIdentificationRecord(
      biosequence_id => $biosequence_id,
      atlas_build_id => $atlas_build_id,
      protein_group_number => $protein_group_number,
      presence_level_id => $presence_level_id,
      represented_by_biosequence_id => $represented_by_biosequence_id,
      probability => $probability,
      confidence => $confidence,
    );
    return ($protein_identification_id);
  }


} # end insertProteinIdentification



###############################################################################
# insertProteinIdentificationRecord --
###############################################################################
sub insertProteinIdentificationRecord {
  my $METHOD = 'insertProteinIdentificationRecord';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $biosequence_id = $args{biosequence_id}
    or die("ERROR[$METHOD]:Parameter biosequence_id not passed");
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]:Parameter atlas_build_id not passed");
  my $protein_group_number = $args{protein_group_number}
    or die("ERROR[$METHOD]:Parameter protein_group_number not passed");
  my $presence_level_id = $args{presence_level_id}
    or die("ERROR[$METHOD]:Parameter presence_level_id not passed");
  my $represented_by_biosequence_id = $args{represented_by_biosequence_id}
    or die("ERROR[$METHOD]:Parameter represented_by_biosequence_id not passed");
  my $probability = $args{probability}
    or die("ERROR[$METHOD]:Parameter probability not passed");
  my $confidence = $args{confidence}
    or die("ERROR[$METHOD]:Parameter confidence not passed");


  #### Define the attributes to insert
  my $rowdata = {
     biosequence_id => $biosequence_id,
     atlas_build_id => $atlas_build_id,
     protein_group_number => $protein_group_number,
     presence_level_id => $presence_level_id,
     represented_by_biosequence_id => $represented_by_biosequence_id,
     probability => $probability,
     confidence => $confidence,
  };

  #### Insert spectrum identification record
  my $protein_identification_id = $sbeams->updateOrInsertRow(
    insert => 1,
    table_name => $TBAT_PROTEIN_IDENTIFICATION,
    rowdata_ref => $rowdata,
    PK => 'protein_identification_id',
    return_PK => 1,
    verbose=>$VERBOSE,
    testonly=>$TESTONLY,
  );

  #### Add it to the cache
  #### (the below lifted from insertSpectrumIdentificationRecord --
  ####   do we want/need it?)
#  our %protein_identification_ids;
#  my $key = "$modified_peptide_instance_id - $spectrum_id - $atlas_search_batch_id";
#  $spectrum_identification_ids{$key} = $spectrum_identification_id;

  return($protein_identification_id);

} # end insertProteinIdentificationRecord


###############################################################################
# insertBiosequenceRelationship --
###############################################################################
sub insertBiosequenceRelationship {
  my $METHOD = 'insertBiosequenceRelationship';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");
  my $reference_biosequence_name = $args{reference_biosequence_name}
    or die("ERROR[$METHOD]: Parameter reference_biosequence_name not passed");
  my $related_biosequence_name = $args{related_biosequence_name}
    or die("ERROR[$METHOD]: Parameter related_biosequence_name not passed");
  my $relationship_name = $args{relationship_name}
    or die("ERROR[$METHOD]: Parameter relationship_name not passed");

  our $counter;

  #### Get the biosequence_ids
  my $reference_biosequence_id = $self->get_biosequence_id(
    biosequence_name => $reference_biosequence_name,
    atlas_build_id => $atlas_build_id,
  );
  my $related_biosequence_id = $self->get_biosequence_id(
    biosequence_name => $related_biosequence_name,
    atlas_build_id => $atlas_build_id,
  );

  #### Get the relationship_type_id
  my $relationship_type_id = $self->get_biosequence_relationship_type_id(
    relationship_name => $relationship_name,
  );

  #### Check to see if this biosequence_relationship is in the database
  my $biosequence_relationship_id = $self->get_biosequence_relationship_id(
    atlas_build_id => $atlas_build_id,
    reference_biosequence_id => $reference_biosequence_id,
    related_biosequence_id => $related_biosequence_id,
  );

  #### If not, INSERT it
  if ($biosequence_relationship_id) {
    if ($VERBOSE) {
      print STDERR "WARNING: Relationship between $reference_biosequence_name".
                 "and $related_biosequence_name already in database\n";
    }
    return ('');
  } else {
    $biosequence_relationship_id = $self->insertBiosequenceRelationshipRecord(
      atlas_build_id => $atlas_build_id,
      reference_biosequence_id => $reference_biosequence_id,
      related_biosequence_id => $related_biosequence_id,
      relationship_type_id => $relationship_type_id,
    );
    return ($biosequence_relationship_id);
  }


} # end insertBiosequenceRelationship



###############################################################################
# insertBiosequenceRelationshipRecord --
###############################################################################
sub insertBiosequenceRelationshipRecord {
  my $METHOD = 'insertBiosequenceRelationshipRecord';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]:Parameter atlas_build_id not passed");
  my $reference_biosequence_id = $args{reference_biosequence_id}
    or die("ERROR[$METHOD]:Parameter reference_biosequence_id not passed");
  my $related_biosequence_id = $args{related_biosequence_id}
    or die("ERROR[$METHOD]:Parameter related_biosequence_id not passed");
  my $relationship_type_id = $args{relationship_type_id}
    or die("ERROR[$METHOD]:Parameter relationship_type_id not passed");


  #### Define the attributes to insert
  my $rowdata = {
     atlas_build_id => $atlas_build_id,
     reference_biosequence_id => $reference_biosequence_id,
     related_biosequence_id => $related_biosequence_id,
     relationship_type_id => $relationship_type_id,
  };

  #### Insert protein identification record
  my $biosequence_relationship_id = $sbeams->updateOrInsertRow(
    insert => 1,
    table_name => $TBAT_BIOSEQUENCE_RELATIONSHIP,
    rowdata_ref => $rowdata,
    PK => 'biosequence_relationship_id',
    return_PK => 1,
    verbose=>$VERBOSE,
    testonly=>$TESTONLY,
  );

  return($biosequence_relationship_id);

} # end insertBiosequenceRelationshipRecord


###############################################################################
# get_biosequence_id --
###############################################################################
sub get_biosequence_id {
  my $METHOD = 'get_biosequence_id';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $biosequence_name = $args{biosequence_name}
    or die("ERROR[$METHOD]: Parameter biosequence_name not passed");
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $query = qq~
	SELECT BS.biosequence_id
	FROM $TBAT_BIOSEQUENCE BS, $TBAT_ATLAS_BUILD AB
	WHERE
	AB.atlas_build_id = $atlas_build_id AND
	AB.biosequence_set_id = BS.biosequence_set_id AND
	BS.biosequence_name = '$biosequence_name'
  ~;
  my ($biosequence_id) = $sbeams->selectOneColumn($query) or
       die "\nERROR: Unable to find the biosequence_id" .
       " with $query\n\n";

  return $biosequence_id;

} # end get_biosequence_id



###############################################################################
# get_presence_level_id --
###############################################################################
sub get_presence_level_id {
  my $METHOD = 'get_presence_level_id';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $level_name = $args{level_name}
    or die("ERROR[$METHOD]: Parameter level_name not passed");

  my $query = qq~
	SELECT protein_presence_level_id
	FROM $TBAT_PROTEIN_PRESENCE_LEVEL
	WHERE level_name = '$level_name'
  ~;
  my ($presence_level_id) = $sbeams->selectOneColumn($query) or
       die "\nERROR: Unable to find the presence_level_id" .
       " with $query\n\n";

  return $presence_level_id;

} # end get_presence_level_id


###############################################################################
# get_biosequence_relationship_type_id --
###############################################################################
sub get_biosequence_relationship_type_id {
  my $METHOD = 'get_biosequence_relationship_type_id';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $relationship_name = $args{relationship_name}
    or die("ERROR[$METHOD]: Parameter relationship_name not passed");

  my $query = qq~
	SELECT biosequence_relationship_type_id
	FROM $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE
	WHERE relationship_name = '$relationship_name'
  ~;
  my ($biosequence_relationship_type_id) = $sbeams->selectOneColumn($query) or
       die "\nERROR: Unable to find the biosequence_relationship_type_id" .
       " with $query\n\n";

  return $biosequence_relationship_type_id;

} # end get_biosequence_relationship_type_id




###############################################################################
# get_protein_identification_id --
###############################################################################
sub get_protein_identification_id {
  my $METHOD = 'get_protein_identification_id';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $biosequence_id = $args{biosequence_id}
    or die("ERROR[$METHOD]:Parameter biosequence_id not passed");
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  #### Lookup and return protein_identification_id
  my $query = qq~
	SELECT protein_identification_id
	FROM $TBAT_PROTEIN_IDENTIFICATION
	WHERE
	atlas_build_id = $atlas_build_id AND
	biosequence_id = '$biosequence_id'
  ~;
  my ($protein_identification_id) = $sbeams->selectOneColumn($query);

  return $protein_identification_id;

} # end get_protein_identification_id


###############################################################################
# get_biosequence_relationship_id  --
###############################################################################
sub get_biosequence_relationship_id {
  my $METHOD = 'get_biosequence_relationship_id';
  my $self = shift || die ("self not passed");
  my %args = @_;

  #### Process parameters
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");
  my $reference_biosequence_id = $args{reference_biosequence_id}
    or die("ERROR[$METHOD]:Parameter reference_biosequence_id not passed");
  my $related_biosequence_id = $args{related_biosequence_id}
    or die("ERROR[$METHOD]:Parameter related_biosequence_id not passed");

  #### Lookup and return biosequence_relationship_id
  my $query = qq~
	SELECT biosequence_relationship_id
	FROM $TBAT_BIOSEQUENCE_RELATIONSHIP
	WHERE
	atlas_build_id = $atlas_build_id AND
	reference_biosequence_id = '$reference_biosequence_id' AND
	related_biosequence_id = '$related_biosequence_id'
  ~;
  my ($biosequence_relationship_id) = $sbeams->selectOneColumn($query);

  return $biosequence_relationship_id;

} # end get_biosequence_relationship_id


###############################################################################
# get_preferred_protid_from_list  --
###############################################################################
# Given a list of protein identifiers, return our most preferred one.
# This could certainly be done faster and more elegantly.
sub get_preferred_protid_from_list {
  my $protid_list_ref = shift;
  my $protid;

  # first, sort the list so that the order of the identifiers in
  # the list doesn't affect what is returned from this function.
  @{$protid_list_ref} = sort(@{$protid_list_ref});

  # prefer a Uniprot (Swiss-Prot) ID
  for $protid (@{$protid_list_ref}) {
    if (($protid =~ /^[ABOPQ].....$/) && ($protid !~ /UNMAPPED/)) {
      return $protid;
    }
  }
  # next, a Swiss-Prot varsplice ID
  for $protid (@{$protid_list_ref}) {
    if (($protid =~ /^[ABOPQ].....-.*$/) && ($protid !~ /UNMAPPED/)) {
      return $protid;
    }
  }
  # next, an Ensembl ID
  for $protid (@{$protid_list_ref}) {
    if (($protid =~ /^ENSP\d\d\d\d\d\d\d\d\d\d\d$/)
             && ($protid !~ /UNMAPPED/)) {
      return $protid;
    }
  }
  # next, any non-DECOY, non-UNMAPPED ID
  for $protid (@{$protid_list_ref}) {
    if (($protid !~ /^DECOY_/) && ($protid !~ /UNMAPPED/)) {
      return $protid;
    }
  }
  # otherwise, return the first ID
  return $protid_list_ref->[0];
}

###############################################################################
=head1 BUGS

Please send bug reports to SBEAMS-devel@lists.sourceforge.net

=head1 AUTHOR

Terry Farrah (tfarrah@systemsbiology.org)

=head1 SEE ALSO

perl(1).

=cut
###############################################################################
1;

__END__
###############################################################################
###############################################################################
###############################################################################
