#!/usr/bin/bash
set -euo pipefail

collection=$1
input=$2

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 COLLECTION_ID INPUT_FILE"
  echo
fi

if [[ ! "$collection" =~ ^[0-9]*$ ]]; then
  echo "COLLECTION_ID muss numerisch sein!"
  exit 1
fi

if [[ $# -eq 1 ]]; then
  grep -e "^$collection," n4o-collections.csv
fi

[[ $# -eq 2 ]] || exit 1


name=Testammlung

if [[ $collection -eq "0" ]]; then
  echo "0 = $name"
else
  name=$(awk -F, "\$1 == $collection {print \$2}" n4o-collections.csv)
  if [[ -z "$name" ]]; then
    echo "COLLECTION_ID $collection unbekannt!"
    exit 1
  fi
fi

dir=import/$collection

receive() {
    echo "## $collection: $name"
    echo
    echo "Empfangene RDF-Daten im Turtle-Format aus \`$input\` "

    original=$dir/original.ttl
    unique=$dir/unique.nt

    tmp=$(mktemp)
    rapper -q -i turtle "$input" | sort | uniq > "$tmp"

    if [[ ! -s "$tmp" ]]; then
        rm "$tmp"
        echo "sind syntaktisch nicht korrekt oder leer!"
        exit 1
    fi

    rm -rf $dir # alten Stand löschen
    mkdir -p $dir

    mv "$tmp" "$unique"
    echo "ist syntaktisch korrektes RDF. "
    echo
    echo "Anzahl unterschiedlicher Tripel: **$(<$unique wc -l)**"
    echo

    # Relative URIs entfernen

    absolute=$dir/absolute.nt

    <$unique awk '$1 !~ /^<file:/ && $2 !~ /<file:/ && $3 !~ /<file:/ { print }' > $absolute
    a=$(<$unique wc -l)
    b=$(<$absolute wc -l)
    removed=$(($a-$b))

    echo "RDF beschränkt auf absolute URIs in \`$absolute\`. "
    if [[ $removed -ne "0" ]]; then
      echo "$removed triples mit relativen URIs entfernt!"
    fi

    # Verschiedene Statistiken

    properties=$dir/properties
    echo
    <$absolute awk '{print $2}' | sed 's/[<>]//g' | sort | uniq -c | sort -nrk1 > $properties
    echo "Statistik der Properties in \`$properties\` mit $(<$properties wc -l) Properties."
    echo "~~~"
    head -3 $properties
    echo "..."
    echo "~~~"

    namespaces=$dir/namespaces
    echo
    # Heuristik zur Extraktion von Namensräumen aus absoluten URIs
    <$absolute awk '{print $1} $3~/^</ {print $3}' | sed 's/^<//' | \
        sed 's/#.*$/#/;t;s|/[^/]*>$|/|;t;s/:.*$/:/' | \
        sort | uniq -c | sort -nrk1 > $namespaces
    echo "Statistik der Namensräume (nur Subjekte und Objekte) in \`$namespaces\` mit $(<$namespaces wc -l) Einträgen. "
    echo "Davon bekannte Namensräume:"
    echo "~~~"
    <$namespaces ./known-namespaces.py
    echo "~~~"
}

receive 2>&1 | tee tmp.md || true
mv tmp.md $dir/README.md

