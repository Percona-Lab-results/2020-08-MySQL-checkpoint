HOST="--mysql-socket=/tmp/mysql.sock"
#HOST="--mysql-host=127.0.0.1"
MYSQLDIR=/mnt/data/vadim/servers/mysql-8.0.21-linux-glibc2.12-x86_64
DATADIR=/mnt/data/mysql8-8.0.21
BACKUPDIR=/data/mysql8-8.0.21-copy
CONFIG=/mnt/data/vadim/servers/my.cnf

set -x
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

startmysql(){
  sync
  sysctl -q -w vm.drop_caches=3
  echo 3 > /proc/sys/vm/drop_caches
  ulimit -n 1000000
  #numactl --interleave=all $MYSQLDIR/bin/mysqld --defaults-file=$CONFIG --basedir=$MYSQLDIR --datadir=$DATADIR $1 &
  systemctl set-environment MYSQLD_OPTS="$1"
  systemctl start mysql-cd
}

shutdownmysql(){
  echo "Shutting mysqld down..."
  systemctl stop mysql-cd
  systemctl set-environment MYSQLD_OPTS=""
  #$MYSQLDIR/bin/mysqladmin shutdown -S /tmp/mysql.sock
}

waitmysql(){
        set +e

        while true;
        do
                $MYSQLDIR/bin/mysql -Bse "SELECT 1" mysql

                if [ "$?" -eq 0 ]
                then
                        break
                fi

                sleep 30

                echo -n "."
        done
        set -e
}

initialstat(){
  cp $CONFIG $OUTDIR
  cp $0 $OUTDIR
}

collect_mysql_stats(){
  $MYSQLDIR/bin/mysqladmin ext -i10 > $OUTDIR/mysqladminext.txt &
  PIDMYSQLSTAT=$!
}
collect_dstat_stats(){
  vmstat 1 > $OUTDIR/vmstat.out &
  PIDDSTATSTAT=$!
}



shutdownmysql

RUNDIR=res-tpcc-`hostname`-`date +%F-%H-%M`


#server: mariadb
#buffer_pool: 25
#randtype: uniform
#io_capacity: 15000
#storage: NVMe

echo "XFS defrag"
#xfs_fsr /dev/nvme0n1
xfs_fsr /dev/sda5
echo 256 > /sys/block/sda/queue/nr_requests
echo 2 > /sys/block/sda/queue/rq_affinity


BP=140
threads=56
i=56

for io in 8000
do
for bpi in 32
do

echo "Restoring backup"
rm -fr $DATADIR
cp -r $BACKUPDIR $DATADIR
chown mysql.mysql -R $DATADIR
#fstrim /data
fstrim /mnt/data

#iomax=$io
iomax=8000
#$(( 3*$io/2 ))

startmysql "--datadir=$DATADIR --innodb-io-capacity=$io --innodb_io_capacity_max=$iomax --innodb_buffer_pool_size=${BP}GB --innodb_buffer_pool_instances=$bpi  --innodb_adaptive_hash_index=0 --innodb_monitor_enable='%'  --innodb_doublewrite_files=2 --innodb_doublewrite_pages=128 " &
# --innodb_doublewrite_files=2 --innodb_doublewrite_pages=128
sleep 10
waitmysql



# perform warmup
#./tpcc.lua --mysql-host=127.0.0.1 --mysql-user=sbtest --mysql-password=sbtest --mysql-db=sbtest --time=3600 --threads=56 --report-interval=1 --tables=10 --scale=100 --use_fk=1 run |  tee -a $OUTDIR/res.txt


runid="io$io.BP${BP}.threads${i}.bpi$bpi"

        OUTDIR=$RUNDIR/$runid
        mkdir -p $OUTDIR
        cp $0 $OUTDIR

echo "server: mysql8" >> $OUTDIR/params.txt
echo "buffer_pool: $BP" >> $OUTDIR/params.txt
echo "io_capacity: $io" >> $OUTDIR/params.txt
echo "threads: $i" >> $OUTDIR/params.txt
echo "storage: SSD" >> $OUTDIR/params.txt
echo "host: `hostname`" >> $OUTDIR/params.txt
echo "buffer_pool_instances: $bpi" >> $OUTDIR/params.txt


        OUTDIR=$RUNDIR/$runid
        mkdir -p $OUTDIR

        # start stats collection


        time=5000
        /mnt/data/vadim/bench/sysbench-tpcc/tpcc.lua --mysql-host=127.0.0.1 --mysql-user=sbtest --mysql-password=sbtest --mysql-db=sbtest --time=$time --threads=$i --report-interval=1 --tables=10 --scale=100 --use_fk=0 --report-csv=yes run |  tee -a $OUTDIR/res.thr${i}.txt


        sleep 30
done

shutdownmysql

done
