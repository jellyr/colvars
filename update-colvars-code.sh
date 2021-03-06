#!/bin/sh
# Script to update a NAMD, VMD, LAMMPS, or GROMACS source tree with the latest colvars code.

# enforce using portable C locale
LC_ALL=C
export LC_ALL

if [ $# -lt 1 ]
then
    cat <<EOF

 usage: sh $0 [-f] <target source tree>

   -f  "force-update": overwrite conflicting files such as Makefile
        (default: create diff files for inspection --- MD code may be different)

   <target source tree> = root directory of the MD code sources
   supported MD codes: NAMD, VMD, LAMMPS, GROMACS

EOF
   exit 1
fi


force_update=0
if [ $1 = "-f" ]
then
  echo Forcing update of all files
  force_update=1
  shift
fi

reverse=0
if [ $1 = "-R" ]
then
  echo Reverse: updating git tree from downstream tree
  reverse=1
  shift
fi

# infer source path from name of script
source=$(dirname "$0")

cpp_patch=${source}/devel-tools/update-header-cpp.patch
tex_patch=${source}/devel-tools/update-header-tex.patch

# check general validity of target path
target="$1"
if [ ! -d "${target}" ]
then
    echo ERROR: Target directory ${target} does not exist
    exit 2
fi

# undocumented option to only compare trees
checkonly=0
[ "$2" = "--diff" ] && checkonly=1
[ $force_update = 1 ] && checkonly=0

# try to determine what code resides inside the target dir
code=unkown
if [ -f "${target}/src/lammps.h" ]
then
  code=LAMMPS
elif [ -f "${target}/src/NamdTypes.h" ]
then
  code=NAMD
elif [ -f "${target}/src/VMDApp.h" ]
then
  code=VMD
elif [ -f "${target}/src/gromacs/commandline.h" ]
then
  code=GROMACS
else
  # handle the case if the user points to ${target}/src
  target=$(dirname "${target}")
  if [ -f "${target}/src/lammps.h" ]
  then
    code=LAMMPS
  elif [ -f "${target}/src/NamdTypes.h" ]
  then
    code=NAMD
  elif [ -f "${target}/src/VMDApp.h" ]
  then
    code=VMD
  elif [ -f "${target}/src/gromacs/commandline.h" ]
  then
    code=GROMACS
  else
    echo ERROR: Cannot detect a supported code in the target directory
    exit 3
  fi
fi

echo Detected ${code} source tree in ${target}
echo -n Updating

# conditional file copy
condcopy() {
  if [ $reverse -eq 1 ]
  then
    a=$2
    b=$1
    PATCH_OPT="-R"
  else
    a=$1
    b=$2
    PATCH_OPT=""
  fi

  TMPFILE=`mktemp`

  # if a patch file is available, apply it to the source file
  # (reversed if necessary)
  if [ "x$3" != "x" ] ; then
    if [ -f "$3" ] ; then
      patch $PATCH_OPT < $3 $a -o $TMPFILE > /dev/null
      # Patched file is new source
      a=$TMPFILE
    fi
  fi

  if [ -d $(dirname "$b") ]
  then
    if [ $checkonly -eq 1 ]
    then
      cmp -s "$a" "$b" || diff -uNw "$b" "$a"
    else
      cmp -s "$a" "$b" || cp "$a" "$b"
      echo -n '.'
    fi
  fi

  rm -f $TMPFILE
}

# check files related to, but not part of the colvars module
checkfile() {
  if [ $reverse -eq 1 ]
  then
    a=$2
    b=$1
  else
    a=$1
    b=$2
  fi
  diff -uNw "${a}" "${b}" > $(basename ${a}).diff
  if [ -s $(basename ${a}).diff ]
  then
    echo "Differences found between ${a} and ${b} -- Check $(basename ${a}).diff and merge changes as needed, or use the -f flag."
    if [ $force_update = 1 ]
    then
      echo "Overwriting ${b}, as requested by the -f flag."
      cp "$a" "$b"
    fi
  else
    rm -f $(basename ${a}).diff
  fi
}

# update LAMMPS tree
if [ ${code} = LAMMPS ]
then

  # update code-independent headers
  for src in ${source}/src/*.h
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/lib/colvars/${tgt}" "${cpp_patch}"
  done
  # update code-independent sources
  for src in ${source}/src/*.cpp
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/lib/colvars/${tgt}" "${cpp_patch}"
  done

  # update LAMMPS interface files (library part)
  for src in ${source}/lammps/lib/colvars/Makefile.* ${source}/lammps/lib/colvars/README
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/lib/colvars/${tgt}"
  done
  # update LAMMPS interface files (package part)
  if [ -f ${target}/src/random_park.h ]
  then
    # versions before 2016-04-22, using old pseudo random number generators
    for src in ${source}/lammps/src/USER-COLVARS/colvarproxy_lammps.cpp \
               ${source}/lammps/src/USER-COLVARS/colvarproxy_lammps.h \
               ${source}/lammps/src/USER-COLVARS/colvarproxy_lammps_version.h \
               ${source}/lammps/src/USER-COLVARS/fix_colvars.cpp \
               ${source}/lammps/src/USER-COLVARS/fix_colvars.h
    do \
      tgt=$(basename ${src})
      condcopy "${src}" "${target}/src/USER-COLVARS/${tgt}" "${cpp_patch}"
    done
    for src in ${source}/lammps/src/USER-COLVARS/Install.sh \
               ${source}/lammps/src/USER-COLVARS/group_ndx.cpp \
               ${source}/lammps/src/USER-COLVARS/group_ndx.h \
               ${source}/lammps/src/USER-COLVARS/ndx_group.cpp \
               ${source}/lammps/src/USER-COLVARS/ndx_group.h \
               ${source}/lammps/src/USER-COLVARS/README
    do \
      tgt=$(basename ${src})
      condcopy "${src}" "${target}/src/USER-COLVARS/${tgt}"
    done
  else
    echo "ERROR: Support for the new pRNG (old LAMMPS-ICMS branch) is currently disabled."
    exit 2
  fi

  # update LAMMPS documentation
  # location of documentation has changed with version 10 May 2016
  test -d "${target}/doc/src/PDF" && docdir="${target}/doc/src" || docdir="${target}/doc"
  for src in ${source}/lammps/doc/*.txt
    do \
      tgt=$(basename ${src})
    condcopy "${src}" "${docdir}/${tgt}"
  done

  cd ${source}/doc
  make colvars-refman-lammps.pdf 1> /dev/null 2> /dev/null
  cd - 1> /dev/null 2> /dev/null
  for src in ${source}/doc/colvars-refman-lammps.pdf
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${docdir}/PDF/${tgt}"
  done

  echo ' done.'
  exit 0
fi

# update NAMD tree
if [ ${code} = NAMD ]
then

  # update code-independent headers
  for src in ${source}/src/*.h
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/src/${tgt}" "${cpp_patch}"
  done
  # update code-independent sources
  for src in ${source}/src/*.cpp
  do \
    tgt=$(basename ${src%.cpp})
    condcopy "${src}" "${target}/src/${tgt}.C" "${cpp_patch}"
  done

  # update NAMD interface files
  for src in \
      ${source}/namd/src/colvarproxy_namd.h \
      ${source}/namd/src/colvarproxy_namd_version.h \
      ${source}/namd/src/colvarproxy_namd.C
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/src/${tgt}" "${cpp_patch}"
  done

  condcopy "${source}/doc/colvars-refman.bib" "${target}/ug/ug_colvars.bib"
  condcopy "${source}/doc/colvars-refman-main.tex" "${target}/ug/ug_colvars.tex" "${tex_patch}"
  condcopy "${source}/doc/colvars-cv.tex" "${target}/ug/ug_colvars-cv.tex" "${tex_patch}"
  condcopy "${source}/namd/ug/ug_colvars_macros.tex" "${target}/ug/ug_colvars_macros.tex" "${tex_patch}"
  condcopy "${source}/doc/colvars_diagram.pdf" "${target}/ug/figures/colvars_diagram.pdf"
  condcopy "${source}/doc/colvars_diagram.eps" "${target}/ug/figures/colvars_diagram.eps"

  echo ' done.'

  # Check for changes in related NAMD files
  for src in \
      ${source}/namd/src/GlobalMasterColvars.h \
      ${source}/namd/src/ScriptTcl.h \
      ${source}/namd/src/ScriptTcl.C \
      ${source}/namd/src/SimParameters.h \
      ${source}/namd/src/SimParameters.C \
      ;
  do \
    tgt=$(basename ${src})
    checkfile "${src}" "${target}/src/${tgt}"
  done
  for src in ${source}/namd/Make*
  do 
    tgt=$(basename ${src})
    checkfile "${src}" "${target}/${tgt}"
  done

  exit 0
fi


# update VMD tree
if [ ${code} = VMD ]
then

  # update code-independent headers
  for src in ${source}/src/*.h
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/src/${tgt}" "${cpp_patch}"
  done
  # update code-independent sources
  for src in ${source}/src/*.cpp
  do \
    tgt=$(basename ${src%.cpp})
    condcopy "${src}" "${target}/src/${tgt}.C" "${cpp_patch}"
  done

  condcopy "${source}/doc/colvars-refman.bib" "${target}/doc/ug_colvars.bib"
  condcopy "${source}/doc/colvars-refman-main.tex" "${target}/doc/ug_colvars.tex" "${tex_patch}"
  condcopy "${source}/doc/colvars-cv.tex" "${target}/doc/ug_colvars-cv.tex" "${tex_patch}"
  condcopy "${source}/vmd/doc/ug_colvars_macros.tex" "${target}/doc/ug_colvars_macros.tex" "${tex_patch}"
  condcopy "${source}/doc/colvars_diagram.pdf" "${target}/doc/pictures/colvars_diagram.pdf"
  condcopy "${source}/doc/colvars_diagram.eps" "${target}/doc/pictures/colvars_diagram.eps"

  # update VMD interface files
  for src in \
      ${source}/vmd/src/colvarproxy_vmd.h \
      ${source}/vmd/src/colvarproxy_vmd_version.h \
      ${source}/vmd/src/colvarproxy_vmd.C  
  do \
    tgt=$(basename ${src})
    condcopy "${src}" "${target}/src/${tgt}" "${cpp_patch}"
  done

  echo ' done.'

  # Check for changes in related VMD files
  for src in ${source}/vmd/src/tcl_commands.C
  do \
    tgt=$(basename ${src})
    checkfile "${src}" "${target}/src/${tgt}"
  done
  for src in ${source}/vmd/configure
  do 
    tgt=$(basename ${src})
    checkfile "${src}" "${target}/${tgt}"
  done

  exit 0
fi


# update GROMACS tree
if [ ${code} = GROMACS ]
then

  echo "Error: the GROMACS implementation of Colvars is not under active development."
  exit 1

  # Copy the colvars source code into gromacs/pulling
  for src in colvaratoms.cpp colvarbias_abf.cpp colvarbias_alb.cpp colvarbias.cpp colvarbias_meta.cpp colvarbias_restraint.cpp colvarcomp_angles.cpp colvarcomp_coordnums.cpp colvarcomp.cpp colvarcomp_distances.cpp colvarcomp_protein.cpp colvarcomp_rotations.cpp colvar.cpp colvargrid.cpp colvarmodule.cpp colvarparse.cpp colvarscript.cpp colvartypes.cpp colvarvalue.cpp colvaratoms.h colvarbias_abf.h colvarbias_alb.h colvarbias.h colvarbias_meta.h colvarbias_restraint.h colvarcomp.h colvargrid.h colvar.h colvarmodule.h colvarparse.h colvarproxy.h colvarscript.h colvartypes.h colvarvalue.h
  do \
    condcopy "src/${src}" "${target}/src/gromacs/pulling/${src}"
  done

  # Copy the GROMACS interface files into gromacs/pulling
  srcDir=${source}/gromacs/src
  for src in colvarproxy_gromacs.cpp colvarproxy_gromacs.h colvars_potential.h
  do \
      condcopy "$srcDir/${src}" "${target}/src/gromacs/pulling/${src}"
  done

  # Find the GROMACS sim_util file, which has changed from
  # sim_util.c to sim_util.cpp between versions.
  if [ -f ${target}/src/gromacs/mdlib/sim_util.cpp ]
  then
      sim_util=${target}/src/gromacs/mdlib/sim_util.cpp
  elif [ -f ${target}/src/gromacs/mdlib/sim_util.c ]
  then
      sim_util=${target}/src/gromacs/mdlib/sim_util.c
  else
      echo "ERROR: Cannot find sim_util.c or sim_util.cpp in the GROMACS source"
      exit 4
  fi
  
  if [ `grep -c colvars $sim_util` -gt 0 ]
  then
      echo "$sim_util appears to already have Colvars modifications. Not modifying."
  else
      # Backup sim_util.
      cp $sim_util ${sim_util}.orig
      
      # Insert necessary pieces of code into the GROMACS sim_util.c or sim_util.cpp.
      awk -f ${source}/gromacs/gromacs-insert.awk ${sim_util}.orig > $sim_util
  fi

  echo ' done.'
  exit 0
fi
