# Unlockr

## Overview

**Unlockr** is a **conditional time-locked payment protocol** designed for secure, automated fund releases based on both **time-based** and **data-driven conditions**. It enables users to lock STX tokens until a specific **block height** is reached *and* an **oracle-based condition** (such as a market price, weather metric, or IoT data point) is satisfied. Unlockr combines decentralized finance automation with oracle integration, ideal for escrowed transactions, milestone payments, and decentralized insurance payouts.

## Key Features

* **Dual-Layer Locking Mechanism**: Payments are only released when both the time and oracle conditions are met.
* **Oracle-Driven Triggers**: Uses external oracle data feeds to evaluate release conditions dynamically.
* **Revocable Payments**: Senders can cancel unfulfilled payments before completion.
* **Oracle Authorization System**: Only contract-approved oracle providers can update data feeds.
* **Secure STX Handling**: Ensures atomic transfers between users and the contract with validation checks.
* **Transparent Tracking**: Every payment is recorded and verifiable through unique transaction IDs.
* **Claimability Checks**: Users can query if a payment is currently eligible for release.

## Contract Components

### Data Maps

* **`payment-transactions`**: Stores conditional payment data including sender, recipient, locked amount, release height, condition key, and fulfillment status.
* **`data-feed-values`**: Holds oracle-provided data such as the current value and the last update block.
* **`oracle-providers`**: Manages the list of authorized oracle addresses allowed to push updates.

### Variables & Constants

* **`tx-counter`**: Tracks sequential payment IDs.
* **Validation Constants**: Define min/max amounts and lock durations for safety.
* **`deployer-address`**: Identifies the contract owner for administrative control.

### Core Functions

* **`create-payment`**: Initiates a new time-locked, condition-based payment and transfers funds to the contract.
* **`set-oracle-value`**: Updates data feeds from verified oracle providers.
* **`claim-payment`**: Allows the recipient to claim funds once both time and oracle conditions are satisfied.
* **`cancel-payment`**: Enables the sender to revoke a pending payment if it has not been claimed.
* **`add-authorized-oracle`**: Adds new oracle providers (owner-only function).

### Read-Only Functions

* **`get-payment-status`**: Returns details of a specific payment.
* **`is-payment-claimable`**: Checks whether a payment meets claim conditions.
* **`get-oracle-value`**: Fetches the latest data value from a feed key.
* **`check-oracle-authorization`**: Verifies if a principal is an authorized oracle.
* **`get-payment-nonce`**: Returns the current payment counter.

## Summary

**Unlockr** establishes a programmable, conditional payment layer on the Stacks blockchain. By combining **time locks** and **oracle-based triggers**, it supports use cases like deferred compensation, smart escrow, and automated DeFi settlements—ensuring **security, transparency, and flexibility** in decentralized fund management.
