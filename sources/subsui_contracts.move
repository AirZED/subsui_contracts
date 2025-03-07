/// Module: subsui_contracts
module subsui_contracts::subsui_contracts;

use sui::coin::{Self, Coin};
use sui::object::{Self, UID};
use sui::sui::SUI;
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

///User Struct
public struct UserProfile has key, store {
    id: UID,
    address: address,
    engagement_score: u64,
    loyalty_points: u64,
    events_attended: vector<UID>,
    membership_tier: u8,
}

public struct PricingTier has store {
    tier_level: u8,
    price: u64,
    required_engagement_score: u64,
}

public struct EventAttendance has key, store {
    id: UID,
    event_id: address,
    attendee: address,
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
    pricing_tiers: vector<PricingTier>,
    staking_enabled: bool,
    staking_apy: u64,
    attendance_count: u64,
    event_category: vector<u8>,
    is_private: bool,
    allowed_attendees: vector<address>,
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
    event_category: vector<u8>,
    is_private: bool,
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
        pricing_tiers: vector::empty(),
        staking_enabled: false,
        staking_apy: 0,
        event_category,
        attendance_count: 0,
        is_private,
        allowed_attendees: vector::empty(),
    };
    transfer::share_object(event)
}

// Helper function to determine price based on user's engagement
fun get_price_for_user(event: &Event, profile: &UserProfile): u64 {
    let mut i = 0;
    let len = vector::length(&event.pricing_tiers);
    let base_price = event.price_per_ticket;

    while (i < len) {
        let tier = vector::borrow(&event.pricing_tiers, i);
        if (profile.engagement_score >= tier.required_engagement_score) {
            return tier.price
        };
        i = i + 1;
    };

    base_price
}

// Regular ticket purchase for anyone
public entry fun buy_ticket(event: &mut Event, payment: &mut Coin<SUI>, ctx: &mut TxContext) {
    assert!(event.is_active, EEventActive);
    assert!(event.tickets_sold < event.max_tickets, EEventSoldOut);
    assert!(coin::value(payment) >= event.price_per_ticket, EInsufficientPayment);

    let ticket = Ticket {
        id: object::new(ctx),
        event_id: object::id_address(event),
        owner: tx_context::sender(ctx),
        purchase_price: event.price_per_ticket,
    };

    event.tickets_sold = event.tickets_sold + 1;
    event.revenue = event.revenue + event.price_per_ticket;

    let paid = coin::split(payment, event.price_per_ticket, ctx);
    transfer::public_transfer(paid, event.creator);
    transfer::transfer(ticket, tx_context::sender(ctx));
}

// Purchase with profile benefits
public entry fun buy_ticket_with_profile(
    event: &mut Event,
    profile: &mut UserProfile,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(event.is_active, EEventActive);
    assert!(event.tickets_sold < event.max_tickets, EEventSoldOut);

    let final_price = get_price_for_user(event, profile);
    assert!(coin::value(payment) >= final_price, EInsufficientPayment);

    let ticket = Ticket {
        id: object::new(ctx),
        event_id: object::id_address(event),
        owner: tx_context::sender(ctx),
        purchase_price: final_price,
    };

    // Only update loyalty points on purchase
    profile.loyalty_points = profile.loyalty_points + 10;

    event.tickets_sold = event.tickets_sold + 1;
    event.revenue = event.revenue + final_price;

    let paid = coin::split(payment, final_price, ctx);
    transfer::public_transfer(paid, event.creator);
    transfer::transfer(ticket, tx_context::sender(ctx));
}

public entry fun add_allowed_attendees(event: &mut Event, address: address, ctx: &mut TxContext) {
    assert!(event.is_private, EUnauthorized);
    assert!(event.creator == tx_context::sender(ctx), EUnauthorized);

    vector::push_back(&mut event.allowed_attendees, address)
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

public entry fun enable_staking(event: &mut Event, apy: u64, ctx: &mut TxContext) {
    assert!(event.creator == tx_context::sender(ctx), EUnauthorized);
    event.staking_enabled = true;
    event.staking_apy = apy;
}

// Attendance tracking functions
public entry fun check_in_attendee(ticket: &Ticket, event: &mut Event, ctx: &mut TxContext) {
    assert!(event.is_active, EEventNotActive);
    assert!(event.creator == tx_context::sender(ctx), EUnauthorized);

    let attendance = EventAttendance {
        id: object::new(ctx),
        event_id: ticket.event_id,
        attendee: ticket.owner,
    };

    event.attendance_count = event.attendance_count + 1;
    transfer::share_object(attendance);
}

// Create user profile
public entry fun create_user_profile(ctx: &mut TxContext) {
    let profile = UserProfile {
        id: object::new(ctx),
        address: tx_context::sender(ctx),
        engagement_score: 0,
        loyalty_points: 0,
        events_attended: vector::empty(),
        membership_tier: 1,
    };
    transfer::transfer(profile, tx_context::sender(ctx))
}

// Add pricing tier to event
public entry fun add_pricing_tier(
    event: &mut Event,
    tier_level: u8,
    price: u64,
    required_engagement_score: u64,
    ctx: &mut TxContext,
) {
    assert!(event.creator == tx_context::sender(ctx), EUnauthorized);

    let tier = PricingTier {
        tier_level,
        price,
        required_engagement_score,
    };
    vector::push_back(&mut event.pricing_tiers, tier)
}

// Update user engagement score
public entry fun update_engagement_score(
    profile: &mut UserProfile,
    points: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == profile.address, EUnauthorized);
    profile.engagement_score = profile.engagement_score + points;

    // Update membership tier based on engagement
    if (profile.engagement_score > 1000) {
        profile.membership_tier = 3; // Gold
    } else if (profile.engagement_score > 500) {
        profile.membership_tier = 2; // Silver
    };
}
