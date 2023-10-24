!#/bin/sh

set -e


FILE=dezoomify-rs
if [[ -f "$FILE" ]]; then
	echo "$FILE exists."	
else
	wget https://github.com/lovasoa/dezoomify-rs/releases/download/v2.11.2/dezoomify-rs-linux.tgz  &&
	tar -xzvf dezoomify-rs-linux.tgz
fi

while IFS=';' read -r col1 col2; do
	echo "$col1"
	./dezoomify-rs --largest "$col1" "$col2"
done < sheets.txt
