#
# Verify that the entries in disklayout.conf match syntactically
# what is specified in the section "Disk layout file syntax"
# in doc/user-guide/06-layout-configuration.adoc
# cf. https://github.com/rear/rear/issues/2006#issuecomment-460646685
#
# Verify that for each 'disk' the 'part' entries in disklayout.conf
# specify consecutive partition device nodes for the disk
# because otherwise "rear recover" would fail with 'parted' error
#   Error: Partition doesn't exist
# cf. https://github.com/rear/rear/issues/1681
#

LogPrint "Verifying that the entries in $DISKLAYOUT_FILE are correct ..."
local keyword dummy junk

Log "Verifying that the 'disk' entries in $DISKLAYOUT_FILE are correct"
# The section "Disk layout file syntax" in doc/user-guide/06-layout-configuration.adoc reads (excerpt)
#   disk <name> <size(B)> <partition label> 
# which is the theory and in practice what matters is what the scripts need that use the 'disk' entries
#   # find usr/share/rear/layout/prepare -type f | xargs grep -l '\^disk'
#   usr/share/rear/layout/prepare/default/300_map_disks.sh
#   usr/share/rear/layout/prepare/default/430_autoresize_all_partitions.sh
#   usr/share/rear/layout/prepare/default/420_autoresize_last_partitions.sh
#   usr/share/rear/layout/prepare/default/250_compare_disks.sh
#   usr/share/rear/layout/prepare/GNU/Linux/100_include_partition_code.sh
# where layout/prepare/GNU/Linux/100_include_partition_code.sh is the most important one
# so that it is used here as reference to decide whether or not the entries are correct:
local broken_disk_entries=()
local disk_dev disk_size parted_mklabel
local broken_part_entries=()
local part_size part_start part_name part_flags part_dev
local partitions=()
local number_of_partitions unused_part_num part_num
local non_consecutive_partitions=()
while read keyword disk_dev disk_size parted_mklabel junk ; do
    test -b "$disk_dev" || broken_disk_entries=( "${broken_disk_entries[@]}" "$disk_dev is not a block device" )
    is_positive_integer $disk_size || broken_disk_entries=( "${broken_disk_entries[@]}" "$disk_dev size $disk_size is not a positive integer" )
    # Here we ignore testing parted_mklabel because create_partitions() in prepare/GNU/Linux/100_include_partition_code.sh has fallbacks

    Log "Verifying that the 'part' entries for $disk_dev in $DISKLAYOUT_FILE are correct"
    # The section "Disk layout file syntax" in doc/user-guide/06-layout-configuration.adoc reads (excerpt)
    #   part <disk name> <size(B)> <start(B)> <partition name/type> <flags/"none"> <partition name>
    # as above layout/prepare/GNU/Linux/100_include_partition_code.sh is the most important one
    # so that it is used here as reference to decide whether or not the entries are correct:
    partitions=""
    while read keyword dummy part_size part_start part_name part_flags part_dev junk ; do
        test -b "$part_dev" || broken_part_entries=( "${broken_part_entries[@]}" "$part_dev is not a block device" )
        is_positive_integer $part_size || broken_part_entries=( "${broken_part_entries[@]}" "$part_dev size $part_size is not a positive integer" )
        is_nonnegative_integer $part_start || broken_part_entries=( "${broken_part_entries[@]}" "$part_dev start $part_start is not a nonnegative integer" )
        partitions=( "${partitions[@]}" "$part_dev" )
        # Using the parted_mklabel fallback behaviour in create_partitions() in prepare/GNU/Linux/100_include_partition_code.sh
        # only when there is no parted_mklabel value, but when there is a parted_mklabel value use it as is:
        if ! test "$parted_mklabel" ; then
            case $part_name in
                (primary|extended|logical)
                    parted_mklabel="msdos"
                    ;;
            esac
        fi
    done < <( grep "^part $disk_dev " "$DISKLAYOUT_FILE" )

    Log "Verifying that the 'part' entries for $disk_dev in $DISKLAYOUT_FILE specify consecutive partitions"
    # The SUSE specific gpt_sync_mbr partitioning scheme is actually a GPT partitioning (plus some compatibility stuff in MBR)
    # see create_partitions() in prepare/GNU/Linux/100_include_partition_code.sh
    test "gpt_sync_mbr" = "$parted_mklabel" && parted_mklabel="gpt"
    # Using the parted_mklabel fallback behaviour in create_partitions() in prepare/GNU/Linux/100_include_partition_code.sh
    # only when there is no parted_mklabel value, but when there is a parted_mklabel value use it as is:
    test "$parted_mklabel" || parted_mklabel="gpt"
    number_of_partitions=${#partitions[@]}
    case $parted_mklabel in
        (gpt)
            # For the GPT partitioning scheme the partitions must have consecutive numbers 1 2 3 ..
            unused_part_num=$(( number_of_partitions + 1 ))
            # We test consecutive partitions only of the form /dev/sdX1 /dev/sdX2 /dev/sdX3
            # up to as many partitions exist for the current disk device:
            for part_num in $( seq $number_of_partitions ) ; do
                # Probably there is a better way to implement that as with dumb nested 'for' loops
                # but note that the partitions in $partitions do not need to be sorted.
                # Better very simple code than oversophisticated (possibly fragile) constructs
                # cf. https://github.com/rear/rear/wiki/Coding-Style
                for partition in "${partitions[@]}" ; do
                    # Partitions that are not of the form $disk_dev$part_num are ignored
                    # so that the test here should not fail for partitions of another form:
                    if test $partition = $disk_dev$part_num ; then
                        # Continue with the next partition number if a partition with the current number was found
                        # and the found partition number is not higher than an unused partition number:
                        test $part_num -lt $unused_part_num && continue 2
                        # otherwise a partition was found where an unused partition number was skipped:
                        non_consecutive_partitions=( "${non_consecutive_partitions[@]}" "Partitions on $disk_dev not consecutive $disk_dev$unused_part_num missing" )
                        break 2
                    fi
                done
                # When no partition with the current number was found there must not be one with a higher number:
                unused_part_num=$part_num
            done
            ;;
        (msdos)
            # TODO:
            # For the MBR partitioning scheme the partitions must not have consecutive numbers.
            # Only primary partitions and a possible extended partition must have consecutive numbers from 1 up to 4.
            # Possible logical partitions must have consecutive numbers 5 6 7 ...
            # There can be a gap between primary/extended partitions
            # e.g. with number 1 and 2 and logical partitions starting at 5
            # cf. https://github.com/rear/rear/issues/1681#issue-286345908
            # Testing consecutive partitions from number 1 up to 4 (i.e. testing consecutive primary an extended partitions):
            unused_part_num=5
            for part_num in $( seq 4 ) ; do
                for partition in "${partitions[@]}" ; do
                    if test $partition = $disk_dev$part_num ; then
                        test $part_num -lt $unused_part_num && continue 2
                        non_consecutive_partitions=( "${non_consecutive_partitions[@]}" "Partitions on $disk_dev not consecutive $disk_dev$unused_part_num missing" )
                        break 2
                    fi
                done
                unused_part_num=$part_num
            done
            # Testing consecutive partitions starting at 5 (i.e. testing consecutive logical partitions):
            unused_part_num=$(( number_of_partitions + 1 ))
            # There cannot be more logical partitions than the total number of partitions on that disk device:
            for part_num in $( seq $number_of_partitions ) ; do
                for partition in "${partitions[@]}" ; do
                    if test $partition = $disk_dev$part_num ; then
                        test $part_num -lt $unused_part_num && continue 2
                        non_consecutive_partitions=( "${non_consecutive_partitions[@]}" "Partitions on $disk_dev not consecutive $disk_dev$unused_part_num missing" )
                        break 2
                    fi
                done
                unused_part_num=$part_num
            done
            ;;
        (*)
            broken_disk_entries=( "${broken_disk_entries[@]}" "$disk_dev partitioning scheme '$parted_mklabel' is neither 'gpt' nor 'msdos'" )
            ;;
    esac

done < <( grep "^disk " "$DISKLAYOUT_FILE" )


# Finally after all tests had been done (so that the user gets all result messages) error out if needed:

# It is a BugError when at this stage the entries in disklayout.conf are not correct
# because just before this script the entries in disklayout.conf were created
# by various 'layout/save' scripts where each of those 'layout/save' scripts
# should error out when it cannot create a valid entry
# (e.g. because of whatever reasons outside of ReaR):
local disklayout_file_is_broken=""
local broken_entry
for broken_entry in "${broken_disk_entries[@]}" ; do
    contains_visible_char "$broken_entry" || continue
    LogPrintError "$broken_entry"
    disklayout_file_is_broken="yes"
done
for broken_entry in "${broken_part_entries[@]}" ; do
    contains_visible_char "$broken_entry" || continue
    LogPrintError "$broken_entry"
    disklayout_file_is_broken="yes"
done
for broken_entry in "${non_consecutive_partitions[@]}" ; do
    contains_visible_char "$broken_entry" || continue
    LogPrintError "$broken_entry"
    disklayout_file_is_broken="yes"
done
is_true "$disklayout_file_is_broken" && BugError "Entries in $DISKLAYOUT_FILE are broken ('rear recover' would fail)"

# Finish this script successfully:
true

