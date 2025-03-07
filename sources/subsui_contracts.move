/// Module: subsui_contracts
module subsui_contracts::subsui_contracts;

use sui::object::{Self, UID};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

/// Ticket Struct
public struct Ticket has key, store {
    id: UID,
    event_id: address,
    owner: address,
}

/// Event Struct
public struct Event has key, store {
    id: UID,
    creator: address,
    name: vector<u8>,
    description: vector<u8>,
    location: vector<u8>,
    date: u64,
    max_tickets: u64,
    price_per_ticket: u64,
    tickets_sold: u64,
    is_active: bool,
}

/// Create a new event
public entry fun create_event(
    creator: address,
    name: vector<u8>,
    description: vector<u8>,
    location: vector<u8>,
    date: u64,
    max_tickets: u64,
    price_per_ticket: u64,
    ctx: &mut TxContext,
) {
    let event = Event {
        id: object::new(ctx),
        creator,
        name,
        description,
        location,
        date,
        max_tickets,
        price_per_ticket,
        tickets_sold: 0,
        is_active: true,
    };
    transfer::public_transfer(event, tx_context::sender(ctx))
}

/// Buy a ticket for an event
public entry fun buy_ticket(event: &mut Event, buyer: address, ctx: &mut TxContext) {
    assert!(event.is_active, 0); // Ensure the event is still active
    assert!(event.tickets_sold < event.max_tickets, 1); // Ensure tickets are available

    // Create a ticket
    let ticket = Ticket {
        id: object::new(ctx),
        event_id: object::id_address(event),
        owner: buyer,
    };

    // Increment tickets sold
    event.tickets_sold = event.tickets_sold + 1;

    // Transfer the ticket to the buyer
    transfer::public_transfer(ticket, buyer);
}

/// Cancel an event
public entry fun cancel_event(event: &mut Event) {
    event.is_active = false;
}
