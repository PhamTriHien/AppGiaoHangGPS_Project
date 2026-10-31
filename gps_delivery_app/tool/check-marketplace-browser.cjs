const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || path.join(process.env.LOCALAPPDATA, 'Temp', 'ghst-browser-check', 'node_modules', 'playwright-core'));

// Isolated UI fixtures. No real identities, orders or cloud writes are used.
(async () => {
  const output = path.resolve(__dirname, '../build/verification');
  await fs.mkdir(output, { recursive:true });
  const browser = await chromium.launch({channel:'msedge',headless:true});
  let activePage;
  try {
    for (const width of process.env.CHECK_WIDTH ? [Number(process.env.CHECK_WIDTH)] : [360,1440]) {
      for (const role of process.env.CHECK_ROLE ? [process.env.CHECK_ROLE] : ['customer','merchant','shop_staff','partner','operator']) {
        const context = await browser.newContext({viewport:{width,height:1000},serviceWorkers:'block'});
        const page = await context.newPage(); activePage = page;
        const errors=[];page.on('pageerror',e=>errors.push(e.message));
        page.on('console',m=>{if(m.type()==='error' && /overflowed|RenderFlex|EXCEPTION CAUGHT/.test(m.text()))errors.push(m.text());});
        page.on('requestfailed',r=>{if(/\.(wasm|ttf|woff2?)$/.test(new URL(r.url()).pathname))console.log('Asset unavailable: '+new URL(r.url()).pathname);});
        const cors={'access-control-allow-origin':'http://127.0.0.1:8080','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,OPTIONS'};
        const uid='00000000-0000-0000-0000-000000000001';
        const user={id:uid,aud:'authenticated',role:'authenticated',email:'browser-fixture@example.com',app_metadata:{provider:'email',providers:['email']},user_metadata:{},identities:[],created_at:new Date().toISOString()};
        const token=`${Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')}.${Buffer.from(JSON.stringify({sub:uid,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')}.fixture`;
        let quantity=0,version=1,submitted=false;
        let returned=false,reviewed=false,favorite=false,shared=false;
        const readNotices=new Set();
        const oid='60000000-0000-0000-0000-000000000001';
        const moid='60000000-0000-0000-0000-000000000002';
        const did='60000000-0000-0000-0000-000000000099';
        const dcode='CL-60000000000000000000000000000099';
        let merchantState='pending',merchantVersion=1;
        let driverOrder={
          id:did,
          tracking_code:dcode,
          status:'searching',
          merchant_ready:true,
          version:1,
          shipping_fee:25000,
          cod_amount:0,
          owner_id:'00000000-0000-0000-0000-000000000009',
          driver_id:null,
          pod_photo_path:'',
          created_at:new Date().toISOString(),
          details:{
            pickup_address:'12 Nguyễn Huệ',
            dropoff_address:'20 Lê Lợi',
            pickup_lat:10.77,
            pickup_lng:106.7,
            dropoff_lat:10.78,
            dropoff_lng:106.71,
            recipient_name:'Người nhận',
            recipient_phone:'0912345678',
            package_description:'Hộp bảo quản thực phẩm',
            weight_kg:1,
            service_type:'standard',
            payment_method:'sender_cash',
            require_pod:true,
            require_otp:true,
          },
        };
        let podUploaded=false,otpVerified=false,lookupCalled=false;
        const finance={id:'70000000-0000-0000-0000-000000000001',order_id:oid,kind:'collection',amount:80000,state:'requested',version:1,proposer:'00000000-0000-0000-0000-000000000002',reason:'Isolated test receipt',evidence:'TEST-RECEIPT'};
        const p={id:'10000000-0000-0000-0000-000000000001',shop_id:'20000000-0000-0000-0000-000000000001',shop_name:'Cửa hàng kiểm thử',name:'Hộp bảo quản thực phẩm',description:'Thông tin kiểm thử riêng cho trình duyệt.',sku:'BOX-01',category:'Gia dụng',price:50000,stock:5,weight_kg:1,image_url:'',published:true,shop_status:'active',paused:false,version:1};
        p.option_groups=[{id:'size',name:'Kích cỡ',min:1,max:1,options:[{id:'small',name:'Cỡ nhỏ',price:5000},{id:'large',name:'Cỡ lớn',price:15000}]}];
        p.preparation_minutes=15;p.images=[];p.available=true;
        const item={product_id:p.id,line_id:'10000000-0000-0000-0000-000000000002',name:p.name,quantity:1,
          unit_price:55000,selected_options:[{group_id:'size',option_id:'small'}],
          options:[{group_name:'Kích cỡ',name:'Cỡ nhỏ',price:5000}]};
        const sh={id:p.shop_id,owner_id:role==='shop_staff'?'00000000-0000-0000-0000-000000000008':uid,name:'Cửa hàng kiểm thử',description:'',address:'12 Nguyễn Huệ',latitude:10.77,longitude:106.7,paused:false,status:'active',version:1,opening_schedule:[],open:true};
        const imageFixture=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=','base64');
        let imageUploaded=false;
        await page.route('**/*.supabase.co/**',route=>{
          const req=route.request();if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:cors});
          const u=new URL(req.url());
          if(u.pathname.startsWith('/storage/v1/object/public/delivery-market-media/'))return route.fulfill({headers:{...cors,'content-type':'image/png'},body:imageFixture});
          if(u.pathname==='/auth/v1/settings')return route.fulfill({headers:cors,json:{external:{google:false}}});
          if(u.pathname==='/auth/v1/token')return route.fulfill({headers:cors,json:{access_token:token,token_type:'bearer',expires_in:3600,refresh_token:'fixture-refresh',user}});
          if(u.pathname==='/auth/v1/user')return route.fulfill({headers:cors,json:user});
          if(u.pathname==='/rest/v1/delivery_api_profiles')return route.fulfill({headers:cors,json:[]});
          return route.fulfill({headers:cors,status:403,json:{message:'Fixture denied'}});
        });
        await page.route('http://127.0.0.1:8787/**',route=>{
          const req=route.request();if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:cors});
          const u=new URL(req.url());const body=req.method()==='POST'?req.postDataJSON():null;const data={headers:cors};
          if(u.pathname==='/delivery/cloud/profile'){
            const roles=role==='partner'?['merchant','driver']:role==='merchant'?['merchant']:[];
            const staffShops=role==='shop_staff'?[{shop_id:sh.id,shop_name:sh.name,role:'staff'}]:[];
            return route.fulfill({...data,json:{schema_version:3,operator:role==='operator',account:{user_id:uid,full_name:'Người kiểm thử',phone:'0901234567',role:role==='merchant'?'merchant':'customer',blocked:false,requested_role:null,
              coin_balance:1500,approved_roles:roles,staff_shops:staffShops,memberships:roles.map(r=>({role:r,state:'active',version:2,reason:''}))}}});
          }
          if(u.pathname==='/delivery/cloud/media'){
            assert.equal(body.shop_id,p.shop_id);assert.ok(body.image.length>0);imageUploaded=true;
            return route.fulfill({...data,json:{image_url:'https://yvnbfurazjbhbopahtmx.supabase.co/storage/v1/object/public/delivery-market-media/ui-only.webp'}});
          }
          if(u.pathname==='/delivery/cloud/pod'){
            assert.equal(body.tracking_code,dcode);assert.ok(body.image.length>0);
            podUploaded=true;driverOrder.pod_photo_path=`pod/${dcode}/pod.webp`;
            return route.fulfill({...data,json:{path:driverOrder.pod_photo_path}});
          }
          if(u.pathname==='/delivery/cloud/addresses')return route.fulfill({...data,json:{addresses:[{id:'30000000-0000-0000-0000-000000000001',label:'Nhà',recipient_name:'Người nhận',recipient_phone:'0912345678',full_address:'20 Lê Lợi',latitude:10.78,longitude:106.71,is_default:true,version:1}]}});
          if(u.pathname==='/delivery/cloud/merchants')return route.fulfill({...data,json:{merchants:[]}});
          if(u.pathname===`/delivery/cloud/orders/${did}/transition`){
            assert.equal(body.version,driverOrder.version);
            if(body.action==='claim'){driverOrder.status='accepted';driverOrder.driver_id=uid;}
            else if(body.action==='arrive')driverOrder.status='arrivingPickup';
            else if(body.action==='pickup')driverOrder.status='inTransit';
            else if(body.action==='deliver'){
              assert.equal(podUploaded,true);
              assert.equal(body.reason,'654321');
              otpVerified=true;
              driverOrder.status='delivered';
            }
            driverOrder.version++;
            return route.fulfill({...data,json:{order:driverOrder}});
          }
          if(u.pathname==='/delivery/cloud/orders'){
            const isQueue=u.searchParams.get('queue')==='true';
            const list=role==='partner'
              ?(isQueue?(driverOrder.status==='searching'?[driverOrder]:[]):(driverOrder.driver_id===uid?[driverOrder]:[]))
              :[];
            return route.fulfill({...data,json:{orders:list,schema_version:3}});
          }
          if(u.pathname==='/delivery/tracking')return route.fulfill({...data,json:{shop_name:p.shop_name,state:'ready',delivery_status:'delivered',updated_at:'2026-10-29',expires_at:'2026-10-30',phone:'PRIVATE_TRACKING_PHONE'}});
          if(u.pathname==='/delivery/tracking/lookup'){
            assert.equal(body.tracking_code,dcode);
            assert.equal(body.phone_last4,'5678');
            lookupCalled=true;
            return route.fulfill({...data,json:{
              tracking_code:dcode,
              status:'delivered',
              service_type:'standard',
              distance_meters:2400,
              created_at:'2026-10-31T08:00:00Z',
              updated_at:'2026-10-31T08:45:00Z',
              timeline:[
                {action:'create',status:'searching',created_at:'2026-10-31T08:00:00Z'},
                {action:'deliver',status:'delivered',created_at:'2026-10-31T08:45:00Z'},
              ],
            }});
          }
          const action=u.pathname.split('/').pop();
          if(!u.pathname.startsWith('/delivery/cloud/marketplace/'))return route.fulfill({...data,status:403,json:{error:'Fixture denied'}});
          if(action==='catalog')return route.fulfill({...data,json:{products:[p],next:null,categories:['Gia dụng'],shop:body.shop_id?sh:null}});
          if(action==='favorites')return route.fulfill({...data,json:{products:favorite?[p]:[],next:null}});
          if(action==='favorite_set'){favorite=body.enabled;return route.fulfill({...data,json:{ok:true}});}
          if(action==='product_details')return route.fulfill({...data,json:{product:p,favorite,reviews:reviewed?[{rating:4,body:'Đã nhận đúng sản phẩm.'}]:[]}});
          if(action==='cart_set'){assert.equal(body.version,version);assert.deepEqual(body.selected_options,item.selected_options);version++;quantity=body.quantity;}
          if(action==='cart'||action==='cart_set')return route.fulfill({...data,json:{version,items:quantity?[{...p,...item,quantity}]:[]}});
          if(action==='quote'){
            assert.equal(body.cart_version,version);assert.equal(body.address_version,1);
            return route.fulfill({...data,json:{quote:{id:'40000000-0000-0000-0000-000000000001',expires_at:new Date(Date.now()+300000).toISOString(),snapshot:{shops:[{shop_name:p.shop_name,items:[item],subtotal:55000,shipping_fee:25000,details:{dropoff_address:'20 Lê Lợi'}}],total:80000}}}});
          }
          if(action==='checkout'){assert.deepEqual(Object.keys(body).sort(),['quote_id','request_key']);submitted=true;quantity=0;return route.fulfill({...data,json:{purchase:{id:'50000000-0000-0000-0000-000000000001',total:80000,payment_status:'UNPAID'}}});}
          if(action==='orders'){
            if(body&&body.workspace==='merchant'){
              return route.fulfill({...data,json:{orders:[{id:moid,shop_id:sh.id,state:merchantState,delivery_status:merchantState==='ready'?'searching':null,version:merchantVersion,reason:'',payment_status:'UNPAID',snapshot:{shop_name:p.shop_name,items:[item],subtotal:55000,shipping_fee:25000}}],next:null}});
            }
            return route.fulfill({...data,json:{orders:submitted?[{id:oid,state:'ready',delivery_status:'delivered',delivered_at:'2026-10-29T00:00:00Z',version:1,reason:'',payment_status:'UNPAID',snapshot:{shop_name:p.shop_name,items:[item],subtotal:55000,shipping_fee:25000}}]:[],next:null}});
          }
          if(action==='order_action'){
            assert.equal(body.order_id,moid);assert.equal(body.version,merchantVersion);
            merchantState=body.action==='accept'?'accepted':'ready';
            merchantVersion++;
            return route.fulfill({...data,json:{ok:true}});
          }
          if(action==='order_services')return route.fulfill({...data,json:{order:{id:oid,owner_id:uid,merchant_id:'00000000-0000-0000-0000-000000000003',state:'ready',delivered_at:'2026-10-29T00:00:00Z',snapshot:{shop_name:p.shop_name,items:[item],subtotal:55000,shipping_fee:25000}},collected:0,refunded:0,settled:0,
            returns:returned?[{id:'80000000-0000-0000-0000-000000000001',order_id:oid,product_id:p.id,quantity:1,reason:'Bị hỏng khi nhận.',state:'requested',response:'',version:1}]:[],
            reviews:reviewed?[{rating:4,body:'Đã nhận đúng sản phẩm.'}]:[],finance:[finance],shares:shared?[{id:'share-1',expires_at:new Date(Date.now()+86400000).toISOString(),revoked_at:null}]:[]}});
          if(action==='return_request'){assert.equal(body.quantity,1);assert.equal(body.product_id,p.id);assert.equal(body.line_id,item.line_id);assert.ok(body.request_key);returned=true;return route.fulfill({...data,json:{ok:true}});}
          if(action==='review_save'){assert.equal(body.rating,4);assert.equal(body.product_id,p.id);reviewed=true;return route.fulfill({...data,json:{ok:true}});}
          if(action==='tracking_share'){shared=true;return route.fulfill({...data,json:{id:'share-1',token:'a'.repeat(64),expires_at:new Date(Date.now()+86400000).toISOString()}});}
          if(action==='tracking_revoke'){shared=false;return route.fulfill({...data,json:{ok:true}});}
          if(action==='operations')return route.fulfill({...data,json:{finance:[finance],returns:[],jobs:{pending:0,failed:0,overdue:0},failed_jobs:[]}});
          if(action==='finance_action'){assert.equal(body.version,finance.version);finance.version++;finance.state=body.action==='approve'?'approved':'completed';return route.fulfill({...data,json:{finance}});}
          if(action==='notifications'||action==='notification_read'){
            if(action==='notification_read')readNotices.add(body.id);
            return route.fulfill({...data,json:{notifications:submitted?['ready','message'].map(kind=>({id:kind,order_id:oid,kind,read_at:readNotices.has(kind)?'2026-10-30T00:00:00Z':null})):[],next:null}});
          }
          if(action==='messages'){
            assert.equal(body.order_id,oid);
            return route.fulfill({...data,json:{messages:[{id:'message-1',body:'Tin nhắn đúng đơn hàng',actor_id:'merchant'}],next:null}});
          }
          if(action==='workspace')return route.fulfill({...data,json:{shops:[sh],products:[p],staff:[],next:null}});
          if(action==='product_save'){assert.equal(body.price,55000);assert.equal(body.version,1);assert.deepEqual(body.option_groups,p.option_groups);assert.equal(body.preparation_minutes,15);assert.deepEqual(body.sale_schedule,[{day:1,open:480,close:1020}]);assert.equal(body.images.length,1);Object.assign(p,body,{version:2});return route.fulfill({...data,json:{product:p}});}
          return route.fulfill({...data,status:403,json:{error:'Fixture denied'}});
        });
        const fill=async(name,value)=>{const field=page.getByRole('textbox',{name,exact:true});await field.scrollIntoViewIfNeeded();await field.click();await field.press('ControlOrMeta+A');await field.pressSequentially(value,{delay:15});await field.press('Tab');};
        const enableSemantics=async()=>{
          await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder')||document.querySelector('flt-semantics'),{timeout:30000});
          await page.locator('flt-semantics-placeholder').evaluateAll(nodes=>nodes.forEach(e=>e.click()));
        };
        const capture=async file=>{
          await page.mouse.move(-20,-20);
          await page.waitForTimeout(500);
          await page.screenshot({path:path.join(output,file)});
        };
        const navigate=async name=>{
          const labels={'Tài khoản':width<860?'Hồ sơ':'Hồ sơ cá nhân',
            'Khám phá':width<860?'Ăn uống':'Ăn uống & Mua sắm',
            'Thông báo':'Trung tâm thông báo','Đơn mua':'Đơn hàng'};
          const label=labels[name]||name;
          await page.getByRole('button',{name:label,exact:true}).or(page.getByText(label,{exact:true})).last().click();
          if(name==='Đơn mua')await page.getByRole('button',{name:'Đơn mua',exact:true}).click();
        };
        await page.goto('http://127.0.0.1:8080/',{waitUntil:'domcontentloaded'});
        await enableSemantics();
        await fill('Email',user.email);await fill('Mật khẩu','fixture-password');
        if(role==='customer')await capture(`market-login-${width}.png`);
        await page.getByRole('button',{name:'Đăng nhập',exact:true}).last().click();
        await page.getByText('Bạn muốn giao hàng hay đặt món đến đâu?',{exact:true}).waitFor({timeout:15000});
        await capture(`ghst-home-${role}-${width}.png`);
        if(role!=='shop_staff'){
          await page.getByText('Bản đồ định vị trực tiếp',{exact:true}).scrollIntoViewIfNeeded();
          const zoom=page.getByText(/^Phóng to \(hoặc cuộn chuột lên\)/).last();
          await zoom.scrollIntoViewIfNeeded();await zoom.click();
          await capture(`ghst-map-${role}-${width}.png`);
          await navigate('Khám phá');
          await page.getByRole('button',{name:'Thêm vào giỏ',exact:true}).waitFor({timeout:15000});
          await capture(`market-catalog-${role}-${width}.png`);
          await page.getByRole('button',{name:'Thêm vào giỏ',exact:true}).click();
          await page.getByRole('checkbox').first().waitFor();
          await capture(`market-options-${role}-${width}.png`);
          await page.getByRole('checkbox').first().click();
          await page.getByRole('button',{name:'Thêm vào giỏ',exact:true}).click();
          await page.getByText('Đã thêm vào giỏ hàng.',{exact:true}).waitFor();
          await page.getByRole('button',{name:'Giỏ hàng',exact:true}).click();
          await page.getByRole('button',{name:'Cập nhật báo giá',exact:true}).click();
          await page.getByRole('button',{name:'Đặt mua',exact:true}).waitFor();
          await page.getByText('Giao đến: 20 Lê Lợi',{exact:true}).waitFor();
          await capture(`market-cart-${role}-${width}.png`);
          await page.getByRole('button',{name:'Đặt mua',exact:true}).click();
          await page.getByText('Giỏ hàng đang trống.',{exact:true}).waitFor();assert.equal(submitted,true);
          await page.getByRole('button',{name:'Back',exact:true}).click();
          await navigate('Đơn mua');
          await page.getByText('Chưa ghi nhận thanh toán',{exact:true}).waitFor();
          await page.getByText('Đã giao',{exact:true}).waitFor();
          await capture(`market-orders-${role}-${width}.png`);
          await page.getByRole('button',{name:'Chi tiết và hậu mãi',exact:true}).click();
          await page.getByRole('button',{name:'Trả hàng',exact:true}).click();
          await fill('Lý do','Bị hỏng khi nhận.');
          await page.getByRole('button',{name:'Xác nhận',exact:true}).click();
          await page.getByLabel(/Trả 1 sản phẩm · Chờ duyệt/).waitFor();assert.equal(returned,true);
          await page.getByRole('button',{name:'Đánh giá',exact:true}).click();
          await page.getByRole('button',{name:'4 sao',exact:true}).click();
          await fill('Nhận xét','Đã nhận đúng sản phẩm.');
          await page.getByRole('button',{name:'Gửi đánh giá',exact:true}).click();
          await page.getByRole('button',{name:'Chia sẻ theo dõi',exact:true}).click();
          await page.getByRole('button',{name:'Sao chép',exact:true}).waitFor();
          await page.keyboard.press('Escape');
          await page.getByRole('button',{name:'Thu hồi liên kết',exact:true}).click();
          await page.getByRole('button',{name:'Thu hồi liên kết',exact:true}).waitFor({state:'hidden'});assert.equal(shared,false);
          await capture(`market-aftersales-${role}-${width}.png`);
          await page.getByRole('button',{name:'Back',exact:true}).click();
          await navigate('Thông báo');
          await page.getByText(`Đơn hàng đã sẵn sàng giao\nĐơn ${oid}`,{exact:true}).click();
          await page.getByText('Dịch vụ đơn mua',{exact:true}).waitFor();
          assert.equal(readNotices.has('ready'),true);
          await page.getByRole('button',{name:'Back',exact:true}).click();
          await capture(`market-notifications-${role}-${width}.png`);
          await page.getByText(`Tin nhắn mới\nĐơn ${oid}`,{exact:true}).click();
          await page.getByText('Tin nhắn đúng đơn hàng\nĐối tác',{exact:true}).waitFor();
          assert.equal(readNotices.has('message'),true);
          await capture(`market-conversation-${role}-${width}.png`);
          await page.getByRole('button',{name:'Back',exact:true}).click();
        }
        if(role==='shop_staff'){
          await navigate('Tài khoản');
          await page.getByText('Cửa hàng của tôi',{exact:true}).last().click();
          await page.getByText('Cửa hàng kiểm thử',{exact:true}).waitFor();
          assert.equal(await page.getByRole('button',{name:'Thêm sản phẩm',exact:true}).isDisabled(),true);
          assert.equal(await page.getByRole('button',{name:'Nhân sự',exact:true}).count(),0);
          await navigate('Tài khoản');
          await page.getByText('Đơn của cửa hàng',{exact:true}).last().click();
          await page.getByRole('button',{name:'Xác nhận đơn',exact:true}).click();
          await page.getByRole('button',{name:'Sẵn sàng giao',exact:true}).waitFor();
          assert.equal(await page.getByRole('button',{name:'Tách kiện giao',exact:true}).count(),0);
          await page.getByRole('button',{name:'Sẵn sàng giao',exact:true}).click();
          await page.getByText('Chờ nhận chuyến',{exact:false}).waitFor();
          assert.equal(merchantState,'ready');
          await capture(`market-shop-staff-${width}.png`);
        }
        if(['merchant','partner'].includes(role)){
          await navigate('Tài khoản');
          if(role==='partner')await page.getByRole('button',{name:'Chuyến giao của tôi',exact:true}).or(page.getByText('Chuyến giao của tôi',{exact:true})).last().waitFor();
          await page.getByText('Cửa hàng của tôi',{exact:true}).last().click();
          await page.getByRole('button',{name:'Sửa sản phẩm',exact:true}).click();
          await fill('Giá bán (đ)','55000');
          const chooser=page.waitForEvent('filechooser');
          await page.getByRole('button',{name:'Chọn ảnh',exact:true}).click();
          await (await chooser).setFiles({name:'product-test.png',mimeType:'image/png',buffer:imageFixture});
          await page.getByRole('button',{name:'Bỏ ảnh',exact:true}).waitFor();assert.equal(imageUploaded,true);
          await capture(`market-editor-${width}.png`);
          await page.getByRole('button',{name:'Thêm khung giờ',exact:true}).click();
          await page.getByRole('button',{name:'Lưu',exact:true}).click();
          await page.getByRole('button',{name:'Thứ hai\n08:00–17:00',exact:true}).waitFor();
          await page.mouse.move(width/2,700);
          await page.mouse.wheel(0,900);
          await page.waitForTimeout(250);
          await capture(`market-editor-options-${width}.png`);
          await page.getByRole('button',{name:'Lưu',exact:true}).click();
          await page.getByRole('button',{name:'Thêm sản phẩm',exact:true}).waitFor();
          if(role==='merchant'){
            await navigate('Tài khoản');
            await page.getByText('Đơn của cửa hàng',{exact:true}).last().click();
            await page.getByRole('button',{name:'Xác nhận đơn',exact:true}).click();
            await page.getByRole('button',{name:'Tách kiện giao',exact:true}).waitFor();
            await page.getByRole('button',{name:'Sẵn sàng giao',exact:true}).click();
            assert.equal(merchantState,'ready');
            await capture(`market-merchant-orders-${width}.png`);
          }
          if(role==='partner'){
            await navigate('Tài khoản');
            await page.getByText('Chuyến giao của tôi',{exact:true}).last().click();
            await page.getByText('Chờ nhận',{exact:true}).last().click();
            await page.getByRole('button',{name:'Nhận chuyến',exact:true}).click();
            await page.getByText('Chuyến của tôi',{exact:true}).last().click();
            await page.getByRole('button',{name:'Đã đến lấy hàng',exact:true}).click();
            await page.getByRole('button',{name:'Đã lấy hàng',exact:true}).click();
            await page.getByRole('button',{name:'Giao thành công',exact:true}).click();
            await page.getByText('Xác thực giao hàng (POD / OTP)',{exact:true}).waitFor();
            const podChooser=page.waitForEvent('filechooser');
            await page.getByRole('button',{name:'Tải ảnh bằng chứng giao hàng (POD)',exact:true}).click();
            await (await podChooser).setFiles({name:'pod-test.png',mimeType:'image/png',buffer:imageFixture});
            await page.getByRole('button',{name:'Đã tải lên ảnh POD',exact:true}).waitFor();
            await fill('Mã OTP 6 số từ người nhận','654321');
            await capture(`ghst-driver-pod-otp-${width}.png`);
            await page.getByRole('button',{name:'Đã giao',exact:true}).click();
            await page.getByText('Đã giao',{exact:true}).waitFor();
            assert.equal(otpVerified,true);
          }
        }
        if(role==='operator'){
          await page.goto('http://127.0.0.1:8080/#/cloud-admin',{waitUntil:'domcontentloaded'});
          await enableSemantics();
          await page.getByRole('button',{name:'Đối soát và hậu mãi',exact:true}).click();
          await page.getByRole('button',{name:'Duyệt',exact:true}).click();await fill('Lý do quyết định','Chứng từ hợp lệ');
          await page.getByRole('button',{name:'Xác nhận',exact:true}).click();
          await page.getByRole('button',{name:'Xác nhận thu/chi',exact:true}).click();await fill('Chứng từ giao dịch đã thực hiện','TEST-VERIFIED-RECEIPT');
          await page.getByRole('button',{name:'Xác nhận',exact:true}).click();
          await page.getByLabel(/Đã xác nhận thu\/chi/).waitFor();assert.equal(finance.state,'completed');
          await capture(`market-finance-${width}.png`);
        }
        await page.goto('http://127.0.0.1:8080/#/share?token='+'a'.repeat(64),{waitUntil:'domcontentloaded'});
        await enableSemantics();
        await page.getByLabel(/Đã giao hàng/).waitFor();
        assert.equal(await page.getByLabel(/PRIVATE_TRACKING_PHONE/).count(),0);
        await capture(`market-public-tracking-${role}-${width}.png`);
        if(role==='customer'){
          await page.goto('http://127.0.0.1:8080/#/track',{waitUntil:'domcontentloaded'});
          await enableSemantics();
          await fill('Mã vận đơn (CL-...) hoặc mã chia sẻ',dcode);
          await fill('4 số cuối SĐT nhận','5678');
          await page.getByRole('button',{name:'Tra cứu',exact:true}).click();
          await page.getByText('NHẬT KÝ HÀNH TRÌNH XÁC THỰC CLOUD',{exact:true}).waitFor();
          assert.equal(lookupCalled,true);
          assert.equal(await page.getByText('0912345678',{exact:false}).count(),0);
          await capture(`cloud-public-lookup-${width}.png`);
        }
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
        assert.deepEqual(errors,[]);
        console.log(`Marketplace ${role} ${width}: PASS`);
        await context.close();
      }
    }
  }catch(e){if(activePage&&!activePage.isClosed()){await activePage.screenshot({path:path.join(output,'market-failure.png')});console.log((await activePage.locator('flt-semantics').allTextContents()).join(' ').slice(0,1600));console.log(await activePage.locator('[aria-label]').evaluateAll(nodes=>nodes.map(e=>({label:e.getAttribute('aria-label'),role:e.getAttribute('role')}))));}throw e;}
  finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
