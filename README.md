# mrndm

## Purpose

- call mrndm
- get the thought out of your head
- move on with your day

## Usage

`mrndm init (-i)`

- run this the first time you use mrndm to register a username and password

`mrndm "We should swap Christmas and Valentine's Day"`

- save this memo and assign the MISC category by default

`mrndm "Call congress about swapping Christmas and Valentine's Day" RMND`

- save this memo and assign the designated RMND category

`mrndm view (-v)`

- view your last five memos

`mrndm view #`

- view the memo with an ID of # (IDs are assigned upon initial submission)

`mrndm view (RMND/TODO/MISC)`

- view all memos you've saved in the designated category

`mrndm view all (-va)`

- view all of your memos 
- i make no promises that this is a good idea

`mrndm delete`

- delete your most recent memo (returns it after deletion)

`mrndm delete #`

- delete the memo with an ID of # (IDs are assigned upon initial submission)

`mrndm auth`

- explicitly generate a new token to establish a handshake with the mrndm server. 
- this is just a failsafe in case something goes wrong, and you shouldn't have to ever call this manually, as it's automatic as a part of the above transactions.