/*
 * SSDT-fake-battery.dsl
 *
 * Injects a fake ACPI battery device into the namespace.
 * Physical laptops have batteries; sandbox VMs almost never do.
 * Malware commonly checks _STA on battery devices as a VM signal.
 *
 * Compile: iasl -tc SSDT-fake-battery.dsl  (produces SSDT-fake-battery.aml)
 * Or use:  bash build-acpi.sh
 *
 * OEM IDs set to Dell OptiPlex 7090 values to match SMBIOS spoofing.
 */

DefinitionBlock ("SSDT-fake-battery.aml", "SSDT", 2, "DELL  ", "DELL7090", 0x00001000)
{
    External (\_SB.PCI0, DeviceObj)

    Scope (\_SB)
    {
        /*
         * Fake AC adapter — always present and online.
         * Real laptops expose this; absence is suspicious.
         */
        Device (AC0)
        {
            Name (_HID, "ACPI0003")  /* ACPI AC Adapter */
            Name (_PCL, Package (1) { \_SB })

            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)  /* Device present, enabled, shown in UI, functioning */
            }

            Method (_PSR, 0, NotSerialized)
            {
                Return (One)   /* Power source online */
            }
        }

        /*
         * Fake battery device — reports a healthy 50% charged Li-Ion battery.
         * _BIF provides design capacity, last full charge capacity, and chemistry.
         * _BST provides current state, remaining capacity, voltage.
         *
         * Values below are consistent with a ~2-year-old Dell 68Wh battery.
         */
        Device (BAT0)
        {
            Name (_HID, "PNP0C0A")     /* ACPI Control Method Battery */
            Name (_UID, Zero)
            Name (_PCL, Package (1) { \_SB })

            Method (_STA, 0, NotSerialized)
            {
                Return (0x1F)  /* Present, enabled, shown in UI, functioning, battery present */
            }

            /* Battery Information — static characteristics */
            Name (_BIF, Package (13)
            {
                Zero,           /* Power unit: mWh */
                0x00010470,     /* Design capacity: 68000 mWh (68 Wh) */
                0x0000F830,     /* Last full charge: 63536 mWh (~93% health) */
                One,            /* Battery technology: rechargeable */
                0x00031734,     /* Design voltage: 202548 mV -> use 11400 (0x2C88) actual */
                0x00000384,     /* Design cap warning: 900 mWh */
                0x00000190,     /* Design cap low: 400 mWh */
                0x00000001,     /* Battery capacity granularity 1 */
                0x00000001,     /* Battery capacity granularity 2 */
                "Primary",      /* Model number */
                "DELL-7DYG4",   /* Serial number */
                "LION",         /* Battery type */
                "Dell Inc."     /* OEM info */
            })

            /* Battery Status — dynamic state */
            Method (_BST, 0, NotSerialized)
            {
                Return (Package (4)
                {
                    0x00000002,     /* State: discharging (bit 1) */
                    0x00000640,     /* Current rate: 1600 mW drain */
                    0x00007D54,     /* Remaining capacity: 32084 mWh (~50%) */
                    0x00002C88      /* Present voltage: 11400 mV */
                })
            }
        }
    }
}
