/// Module: subsui_contracts
module subsui_contracts::subsui_contracts;

use sui::coin::{Self, Coin};
use sui::object::{Self, UID};
use sui::sui::SUI;
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// Error contraints
const EEventNotActive: u64 = 1;
const EEventSoldOut: u64 = 2;
const ESelfTransfer: u64 = 3;
const EEventActive: u64 = 4;
const EInsufficientPayment: u64 = 5;
const EUnauthorized: u64 = 6;

/// Ticket Struct
public struct Ticket has key, store {
    id: UID,
    event_id: address,
    owner: address,
    purchase_price: u64,
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
    revenue: u64,
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
        revenue: 0,
    };
    transfer::share_object(event)
}

/// Buy a ticket for an event
public entry fun buy_ticket(event: &mut Event, payment: &mut Coin<SUI>, ctx: &mut TxContext) {
    assert!(event.is_active, EEventActive); // Ensure the event is still active
    assert!(event.tickets_sold < event.max_tickets, EEventSoldOut); // Ensure tickets are available
    assert!(coin::value(payment) >= event.price_per_ticket, EInsufficientPayment); // Ensure the payment is sufficient

    // Create a ticket
    let ticket = Ticket {
        id: object::new(ctx),
        event_id: object::id_address(event),
        owner: tx_context::sender(ctx),
        purchase_price: event.price_per_ticket,
    };

    // Increment tickets sold
    event.tickets_sold = event.tickets_sold + 1;
    event.revenue = event.revenue + event.price_per_ticket;

    // Transfer the ticket to the buyer
    let paid = coin::split(payment, event.price_per_ticket, ctx);
    transfer::public_transfer(paid, event.creator);
    transfer::transfer(ticket, tx_context::sender(ctx));
}

public entry fun transfer_ticket(ticket: &mut Ticket, new_owner: address, ctx: &mut TxContext) {
    assert!(ticket.owner == tx_context::sender(ctx), EUnauthorized);
    assert!(ticket.owner != new_owner, ESelfTransfer); // Prevent transferring to self

    ticket.owner = new_owner;
}

public entry fun refund_ticket(
    ticket: Ticket,
    event: &mut Event,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(!event.is_active, EEventActive); // Only refund if event is canceled
    assert!(event.creator == tx_context::sender(ctx), EUnauthorized);

    event.tickets_sold = event.tickets_sold - 1;
    event.revenue = event.revenue - ticket.purchase_price;

    // Return funds to ticket owner
    let paid = coin::split(payment, ticket.purchase_price, ctx);
    transfer::public_transfer(paid, ticket.owner);

    let Ticket { id, event_id: _, owner: _, purchase_price: _ } = ticket;
    object::delete(id);
}

/// Cancel an event
public entry fun cancel_event(event: &mut Event, ctx: &mut TxContext) {
    assert!(event.creator == tx_context::sender(ctx), EUnauthorized);
    event.is_active = false;
}
