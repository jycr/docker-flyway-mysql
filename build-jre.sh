#!/usr/bin/env bash
__BASEDIR="$(readlink -f "$(dirname "$0")")";if [[ -z "$__BASEDIR" ]]; then echo "__BASEDIR: undefined";exit 1;fi

installPackageIfCommandNotFound() {
  local cmd="$1"
  local pkg="$2"

  if ! command -v ${cmd}; then
    DEBIAN_FRONTEND=noninteractive \
    apt-get update \
    && apt-get install -y -qq \
      ${pkg} \
    && rm -rf /var/lib/apt/lists/* \
    || return $?
  fi

}


optimizeLibJvm(){
  local outputDir="$1"

  echo "Built JRE: $(du -sh "$outputDir")"

  # See: https://github.com/docker-library/openjdk/issues/217
  echo "... optimizing libjvm.so size ..."

  installPackageIfCommandNotFound strip binutils

  strip -p --strip-unneeded "$outputDir/lib/server/libjvm.so" \
  || return $?

  echo "Built JRE: $(du -sh "$outputDir")"
}

optimizeJars(){
  local file="$1"

  echo "... optimize JARs size ..."
  installPackageIfCommandNotFound advzip advancecomp

  for file in "$@"; do
    advzip -4 -a "$file.recompress" "$file" \
    && ls -ldh "$file.recompress" "$file" \
    && rm -f "$file" \
    && mv "$file.recompress" "$file" \
    || return $?
  done
}

main(){
  local jarsDir="$1"
  local outputDir="$2"

  local _retCode=0

  local jarsList=`find "$jarsDir" -name '*.jar'`

  echo "Find modules for:"
  echo "$jarsList"

  local modules=`jdeps --list-deps ${jarsList} | sed -E 's, +,,' | tr '\n' ',' | sed -E 's/^,|,$//g'`

  echo "Build JRE with modules: $modules"
  jlink \
    --verbose \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --strip-debug \
    --add-modules "$modules" \
    --output "$outputDir" \
  || return $?

  optimizeLibJvm "$outputDir"

  # Uncomment following line to recompress JAR files
  #optimizeJars ${jarsList}
}

main "$__BASEDIR/target/dependency/" "$__BASEDIR/target/java-runtime"
exit $?
