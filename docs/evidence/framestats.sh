#!/bin/bash
# Frame-interval stats from `dumpsys SurfaceFlinger --latency <layer>`.
# Line 1 = refresh period (ns). Following lines: desiredPresent actualPresent frameReady.
f="$1"
refresh=$(awk 'NR==1{printf "%.4f", $1/1000000}' "$f")
awk 'NR>1 && $2>0 && $2<9223372036854775807{print $2}' "$f" \
  | awk 'NR>1{d=($1-p)/1000000; if(d>0 && d<2000) print d} {p=$1}' \
  | sort -n > "$f.iv"
awk -v refresh="$refresh" '{iv[NR]=$1; sum+=$1; if($1>refresh*1.5) jank++} END{
  n=NR; if(n<2){print "insufficient frames"; exit}
  printf "  refresh period       : %.2f ms (%.0f Hz)\n", refresh, 1000/refresh
  printf "  frame intervals      : %d\n", n
  printf "  mean                 : %.2f ms  (%.1f fps effective)\n", sum/n, 1000/(sum/n)
  printf "  p50                  : %.2f ms\n", iv[int(n*0.50)]
  printf "  p90                  : %.2f ms\n", iv[int(n*0.90)]
  printf "  p95                  : %.2f ms\n", iv[int(n*0.95)]
  printf "  p99                  : %.2f ms\n", iv[int(n*0.99)]
  printf "  worst                : %.2f ms\n", iv[n]
  printf "  janky (>1.5x budget) : %d of %d (%.1f%%)\n", jank, n, jank*100/n
}' "$f.iv"
