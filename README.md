# mrndm

## Purpose

- call mrndm
- get the thought out of your head
- move on with your day

## Usage

`(path/to/package/)mrndm.sh init (-i)`

- Installs mrndm on your PATH and creates a config file. Run this before you do anything else.

`mrndm register (-r)`

- Registers a username and password and uses them to retrieve a token, which is saved to the config file.

`mrndm sync` (alias: `mrndm login`)

- Run this when you're using mrndm on a new device for the first time or to regenerate a stale token (will prompt for username & password)

`mrndm logout (-l)`

- Log out of your current mrndm session and removes your session token from the config file

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

`mrndm help (-h)`

- view the full help screen (which looks suspiciously like this README)
