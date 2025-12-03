module wait_list::contribution;


use sui::clock::Clock;


public struct WarlotData has drop, store {
    interaction_points: u64,
    last_interaction_time: u64,
}

// init 
public(package) fun create(): WarlotData { WarlotData{interaction_points: 0, last_interaction_time: 0}}


// get interaction points
public fun interaction_points(wd: &WarlotData): u64 {
    wd.interaction_points
}

// get last interaction time
public fun last_interaction_time(wd: &WarlotData): u64 {
    wd.last_interaction_time
}



public(package) fun update_points (wd: &mut WarlotData, points: u64, clock: &Clock){
    wd.interaction_points = wd.interaction_points + points; 
    wd.last_interaction_time = clock.timestamp_ms();
}

public(package) fun destroy (wd: WarlotData){
    WarlotData{interaction_points: _, last_interaction_time: _} = wd
}