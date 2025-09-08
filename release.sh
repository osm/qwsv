#!/usr/bin/env bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
	echo "usage: <base dir> <version> <changelog>"
	exit
fi

base_dir="$1"
version="$2"
changelog="$3"

targets=(freebsd-amd64 linux-amd64 linux-arm64)

output_dir="/tmp/qwsv-v$version"
output_artifacts="$output_dir/artifacts.txt"

download_artifacts() {
	repo="$(echo $1 | cut -d: -f1)"
	branch="$(echo $1 | cut -d: -f2)"
	id="$(echo $1 | cut -d: -f3)"

	echo $1 >>$output_artifacts

	if [ ! -d "$base_dir/$repo" ]; then
		echo "error: $base_dir/$repo doesn't exist" >&2
		exit 1
	fi

	if [ "$repo" = "mvdsv" ] && [ "$branch" = "master" ]; then
		art="mvdsv"
		dl_file="mvdsv"
		perm="755"
		output_file="mvdsv-antilag"
	elif [ "$repo" = "mvdsv" ] && [ "$branch" = "non-antilag" ]; then
		art="mvdsv-non-antilag"
		dl_file="mvdsv"
		perm="755"
		output_file="mvdsv"
	elif [ "$repo" = "ktx" ] && [ "$branch" = "master" ]; then
		art="qwprogs"
		dl_file="qwprogs.so"
		perm="644"
		output_file="qwprogs-antilag.so"
	elif [ "$repo" = "ktx" ] && [ "$branch" = "non-antilag" ]; then
		art="qwprogs-non-antilag"
		dl_file="qwprogs.so"
		perm="644"
		output_file="qwprogs.so"
	elif [ "$repo" = "qwfwd" ] && [ "$branch" = "master" ]; then
		art="qwfwd"
		dl_file="qwfwd"
		perm="755"
		output_file="qwfwd"
	elif [ "$repo" = "qtv-go" ] && [ "$branch" = "master" ]; then
		art="qtv-go"
		dl_file="qtv-go"
		perm="755"
		output_file="qtv-go"
	else
		echo "error: unknown repo and/or branch: $repo/$branch" >&2
		exit 1
	fi

	pushd "$base_dir/$repo" >/dev/null

	NO_COLOR=1 gh run list --json databaseId,headBranch --limit 20 \
		| jq -e --argjson id "$id" --arg branch "$branch" \
		'.[] | select(.databaseId == $id and .headBranch == $branch)' >/dev/null
	if [ $? -ne 0 ]; then
		echo "error: run with id=$id and branch=$branch not found in $repo" >&2
		exit 1
	fi

	for target in "${targets[@]}"; do
		rm -f "$dl_file"
		gh run download "$id" -n "$art-$target"
		chmod "$perm" "$dl_file"
		mv "$dl_file" "$output_dir/$target-$output_file"
	done

	popd >/dev/null
}

if [ ! -f "$changelog" ]; then
	echo "error: unable to find $changelog" >&2
	exit 1
fi

artifacts=()
in_version=0
in_section=0

while IFS= read -r line; do
	if [[ "$line" =~ ^##\ \[$version\] ]]; then
		in_version=1
		continue
	fi

	if [[ $in_version -eq 1 && "$line" =~ ^##\  ]]; then
		break
	fi

	if [[ $in_version -eq 1 && $in_section -eq 0 && "$line" == "### Built Artifacts" ]]; then
		in_section=1
		continue
	fi

	if [[ $in_section -eq 1 ]]; then
		if [[ "$line" =~ ^###\  ]]; then
			break
		fi

		if [[ "$line" =~ ^-\ \`(.+)\`$ ]]; then
			artifact="${line#- \`}"
			artifact="${artifact%\`}"
			artifacts+=("$artifact")
		fi
	fi
done < "$changelog"

if [ ${#artifacts[@]} -eq 0 ]; then
	echo "error: no artifacts found for version: $version" >&2
	exit 1
fi

rm -rf $output_dir
mkdir -p $output_dir

for artifact in "${artifacts[@]}"; do
	download_artifacts $artifact
done

cp README.md $output_dir
cp CHANGELOG.md $output_dir

tar cfz qwsv-v$version.tar.gz -C $(dirname $output_dir) $(basename $output_dir)
rm -rf $output_dir
