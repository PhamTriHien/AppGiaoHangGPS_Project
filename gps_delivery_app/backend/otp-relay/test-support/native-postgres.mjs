import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, writeFile, rm, readFile } from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import { randomBytes } from 'node:crypto';
import pg from 'pg';

const execute=promisify(execFile);

// Always provisions a disposable, loopback-only cluster; never reads .env or a
// caller-supplied database URL, so production credentials cannot reach this test.
export async function startNativePostgres() {
  const platform={win32:'windows',linux:'linux',darwin:'darwin'}[process.platform];
  if(!platform)throw new Error('Unsupported PostgreSQL test platform');
  const binaries=await import(`@embedded-postgres/${platform}-${process.arch}`);
  const root=path.resolve(import.meta.dirname,'../../../build/verification');
  await mkdir(root,{recursive:true});
  const directory=await mkdtemp(path.join(root,'postgres-test-'));
  const relative=path.relative(root,directory);
  if(!relative||relative.startsWith('..')||path.isAbsolute(relative))throw new Error('Unsafe PostgreSQL test directory');
  const data=path.join(directory,'data'), pwfile=path.join(directory,'init-password');
  const password=randomBytes(32).toString('hex');
  const options={windowsHide:true,timeout:30000,maxBuffer:2_000_000};
  let started=false;
  const stop=async()=>{
    // pg_ctl can time out after the server has started. Check the actual server
    // before removing files rather than relying only on the startup return code.
    let running=started;
    if(!running){
      try{await execute(binaries.pg_ctl,['-D',data,'status'],options);running=true;}
      catch(error){if(![3,4].includes(error.code))throw error;}
    }
    if(running){await execute(binaries.pg_ctl,['-D',data,'-m','fast','-w','stop'],options);started=false;}
    await rm(directory,{recursive:true,force:true});
  };
  try{
    const port=await new Promise((resolve,reject)=>{
      const server=net.createServer();server.on('error',reject);
      server.listen(0,'127.0.0.1',()=>{const selected=server.address().port;server.close(error=>error?reject(error):resolve(selected));});
    });
    await writeFile(pwfile,password,{mode:0o600});
    try{
      await execute(binaries.initdb,['-D',data,'--username=ghst_test','--auth-host=scram-sha-256','--auth-local=trust',
        `--pwfile=${pwfile}`,'--locale=C','--encoding=UTF8'],options);
    }finally{await rm(pwfile,{force:true});}
    await execute(binaries.pg_ctl,['-D',data,'-l',path.join(directory,'server.log'),'-o',
      `-h 127.0.0.1 -p ${port} -c max_connections=60 -c wal_level=logical -c statement_timeout=15000 -c lock_timeout=10000`,'-w','start'],options);
    started=true;
    const settings={host:'127.0.0.1',port,user:'ghst_test',password,database:'postgres',ssl:false,
      connectionTimeoutMillis:5000,query_timeout:20000};
    return {directory,settings,client:()=>new pg.Client(settings),stop,
      log:()=>readFile(path.join(directory,'server.log'),'utf8')};
  }catch(error){await stop();throw error;}
}
