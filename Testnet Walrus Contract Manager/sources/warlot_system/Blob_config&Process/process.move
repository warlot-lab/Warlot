module warlot::process;
// // todo
// // get work list form bot ✅
// // renew worklist
// //  confirm work list
// //  return unrenewd list


// // system renew list of blobs

// public fun renew(
//     _: &mut AdminCap,
//     system_cfg: &mut SystemConfig,
//     walrus_system: &mut System,
//     users: vector<address>,
//     epoch_set: u32,
//   // estimate: vector<u64>,
//     ctx: &mut TxContext
// ): vector<address> {
//     let insufficient = vector::empty<address>();
//     let mut i = 0;

//     while (i < vector::length(&users)) {
//         let user_addr = *vector::borrow(&users, i);
       

//         let mut funds = {
//             let user_ref = get_user_mut(system_cfg, user_addr);
//             let wallet   = user_ref.get_wallet();
//             wallet.get_balance(ctx)
//         };

//         let process_state = option::none();
       
//         //process each blob
//         process_blob(system_cfg, user_addr, epoch_set, walrus_system, &mut funds, &process_state);
        

//     //   return any leftover token
//         {
//             let user_ref3 = get_user_mut(system_cfg, user_addr);
//             user_ref3.get_wallet().return_balance(funds);
//         };

//         i = i + 1;
//     };

//     insufficient
// }






// // system sync_blob
// public fun sync_blob( 
//     _: &mut AdminCap,
//     system_cfg: &mut SystemConfig,
//     walrus_system: &mut System,
//     users: vector<address>,
//     epoch_set: u32,
//     epoch_checkpoint: u32,
//     ctx: &mut TxContext){

//     let mut i = 0;

//     while (i < vector::length(&users)) {
//         let user_addr = *vector::borrow(&users, i);
        
//     //    get funds 
//         let mut funds = {
//             let user_ref = get_user_mut(system_cfg, user_addr);
//             let wallet   = user_ref.get_wallet();
//             wallet.get_balance(ctx)
//         };


//     // create processSync state
//         let process_state =  option::some(ProcessSync{epoch_checkpoint});
       
//         //process each blob
//         process_blob(system_cfg, user_addr, epoch_set, walrus_system, &mut funds, &process_state);
        
//     //   return any leftover token
//         {
//             let user_ref3 = get_user_mut(system_cfg, user_addr);
//             user_ref3.get_wallet().return_balance(funds);
//         };

//         i = i + 1;
//     };

// }




// fun process_blob(
//     system_cfg: &mut SystemConfig,
//     user_addr: address,
//     epoch_set: u32,
//     walrus_system: &mut System,
//     funds: &mut Coin<WAL>,
//     process_state: &Option<ProcessSync>){
//         //  this get the sync pad epoch of that particular blob
//             let mut sync_epoch: u32;

//             // get the user object 
//             let user_ref2 = get_user_mut(system_cfg, user_addr);

//             //get the blob_cfg objects for that epoch
//             let blob_list     = user_ref2.get_mut_obj_list_blob_cfg(epoch_set);
//             let mut y = 0;
//             while (y < blob_config_vec::length(blob_list)) {
//                 // store the current value of the token before the sync
//                 // this is for the event to be able to emit the actual cost of renewal of the data 
//                 let  funds_current_balance = funds.value();
//                 // this holds the mut ref to that particular blob in that index
//                 let blob_cfg_ref = blob_config_vec::borrow_mut(blob_list, y);
               
            
            
//                 if (option::is_some(process_state)){
//                         sync_epoch = config::sync_epoch_count(blob_cfg_ref, walrus_system, option::borrow(process_state).epoch_checkpoint, );
//                 }else{
//                     if (blob_cfg_ref.cycle_at() != blob_cfg_ref.cycle_end()){return};
//                     sync_epoch = config::get_renew_epoch_count(blob_cfg_ref, walrus_system, epoch_set);

//                 };
            
                   
//                     // this makes sure that only the ones that need padding gets padded 
//                     if (sync_epoch > 0){
//                         // setting 0 as place holder for the renewal to be changed in update
//                         if (!option::is_some(process_state)){let _ =blob_cfg_ref.reduce_cycle();};


//                         // get the blob form the blob config
//                         let blob_obj   = blob_cfg_ref.blob();

                   
//                         extend_blob(walrus_system, blob_obj, funds, sync_epoch);
//                         event::emit_renew_digest(
//                             user_addr, 
//                             blob_cfg_ref.get_blob_obj_id(),
//                             epoch_set,
//                             funds_current_balance - funds.value(),
//                             blob_cfg_ref.blob_cfg_size()
//                         );

//                         event::emit_update_blob(user_addr, blob_cfg_ref.get_blob_obj_id(), blob_cfg_ref.blob_current());

//                     };
          
//                 y = y + 1;
//             };


// }

