;============================================================================
;Program    : CPUFreq
;Version    : 3
;Author     : Cleber Jean Barranco <cleberjean@hotmail.com>
;Date       : 02jun2026
;License    : MIT (See LICENSE file)
;
;Description: Show current CPU frequency in DOS (Real Mode) by
;             reading the CPU clock through of APERF (0xE8) MSR
;             or TSC register and show as "#.## GHz".
;
;To Compile : "nasm cpufreq.asm -o cpufreq.com" or
;             "fasm cpufreq.asm cpufreq.com"
;
;NOTE ABOUT OF FASM USE: It may generate 80386 conditional jumps, that can
;                        turn the binary file incompatible with 16 bits
;                        processors (8086/8088, 80186 and 80286), causing
;                        crashing on the execution. See the solution on
;                        Bad_Proc_Near_Jump label below.
;
;============================================================================

;============================================================================
;History:
;--------
;    10may2026
;        + Changed Real Mode checking by the use of SMSW instruction
;          (MOV EAX,CR0 NOT WORKS in Windows 3.1 in Enhanced Mode).
;        + Created the Bad_Proc_Near_Jump label, after 286 checking routine,
;          to fix the ausence of a near conditional instruction on 16 bits
;          processors.
;
;    02jun2026
;        + Checking if interrupt 67h exists, before check if EMM386.EXE is
;          loaded.
;============================================================================


;Defines    
    APERF_MSR_FLAG      equ 1
    IA32_MPERF_MSR      equ 0x000000E7
    IA32_APERF_MSR      equ 0x000000E8
    TSC_REG_FLAG        equ 00010000b
    INVARIANT_TSC_FLAG  equ 1
    FALSE               equ 0
    TRUE                equ 1


;Directive for .COM file    
    org  100h                      ; program is a DOS .COM file

    
;Get DOS Version and Store for Support Checking of INT 21h 0x4C Function
    mov    ax,3000h
    int    21h                     ; get DOS version
    mov    [DOS_VERSION],al        ; and store for checkings


;Processor Detection
;Double check for 8086/8088.
;Taken from Intel Pentium Processor User's Manual, Volume 3, 
;Chapter 5.3 - SAMPLE CPUID IDENTIFICATION/FPU DETECTION CODE,
;pages 129 to 123, from 1993.
;Example 5-1. CPU Identification and FPU Detection.
;The original commentary says:
;       "This program has been developed by Intel Corporation. You have
;        Intel's permission to incorporate this source code into your
;        product royalty free."
;
;Author Note: Only CX register was changed to BX.
;
;Processors later of 8086 always push SP to stack, and then decrement SP 
;by 2. 8086 always decrement SP by 2 and then push it on stack.
;Also bits 12..15 are always set on the 8086 processor.
;[MODIFIED] Test only bits 14 and 15, due a detection fail when in Priviligied Level != 0.
Test_8086:
    push   sp                      ; Push SP
    pop    ax                      ; And restore in AX
    sub    ax,sp                   ; Will clear AX if CPU is an 80286 or later
    jnz    Bad_Proc_Near_Jump      ; Processor is an 80186 or early
    pushf
    pop    bx                      ; Save FLAGS in BX
    mov    ax,bx                   ; Copy flags to AX
    and    ax,0FFFh                ; Clear bits 12..15
    push   ax
    popf                           ; Clear bits 12..15 in FLAGS
    pushf
    pop    ax                      ; Copy flags again to AX
;    and    ax,0F000h               ; Check if bits 12..15 still always clean
;    jnz    Bad_Proc                ; Bits 12..15 from Flags Register remain set (processor is an 8086/80186)
    and    ax,0C000h               ; Check if bits 14 and 15 still always clean
    jnz    Bad_Proc_Near_Jump      ; Bits 14 and 15 from Flags Register remain set (processor is an 8086/80186)


;Intel 286 CPU Checking
;Bits 12-15 are always clear on the Intel 286 processor.
Test_80286:
    mov    ax,bx                   ; Copy flags to AX
    or     ax,0F000h               ; Set bits 12..15
    push   ax
    popf
    pushf
    pop    ax
    and    ax,0F000h               ; If bits 12..15 are cleared, then CPU=80286
    jnz    Test_80386              ; processor is an 80386
         
         
;Conditional Near Jump Fix for the 16 bits Processors
;Processors 8086/8088, 80186 and 80286 has Conditional Short Jumps Only.
Bad_Proc_Near_Jump:           
    jmp    Bad_Proc

           
           ;+----------------------------------------------------+;
           ;| Starting here, is safe to use 32 bits instructions |;
           ;+----------------------------------------------------+;

;Intel386 CPU Checking
;The AC bit, bit #18, is a new bit introduced in the EFLAGS
;register on the Intel486 DX CPU to generate alignment faults.
;This bit can not be set on the Intel386 CPU.
Test_80386:
    push   bx
    popf                           ; Restore original FLAGS
    pushfd
    pop    ebx                     ; Save original EFLAGS in EBX
    mov    eax,ebx                 ; Copy original EFLAGS to EAX
    xor    eax,40000h              ; Flip AC bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax                     ; Get new EFLAGS value
    xor    eax,ebx                 ; Compare original EFLAGS with new EFLAGS. Can't
                                   ; toggle AC bit, CPU=80386
    jz     Bad_Proc

Test_80486:
    mov    eax,ebx                 ; Copy original EFLAGS to EAX
    xor    eax,200000h             ; Flip ID bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax                     ; Get new EFLAGS value
    xor    eax,ebx                 ; Compare original EFLAGS with new EFFAGS
    jz     Bad_Proc                ; If ID bit cannot be changed, CPU=80486
                                   ; without CPUID instruction functionality

;For safety only, restore original EFLAGS (not is on original source code)
    push   ebx
    popfd


;Now is safe to use the CPUID instruction to get processor informations
    xor    eax,eax                 ; clear EAX
    cpuid
    cmp    al,1                    ; check # of leaves supported by CPUID
    jb     Bad_Proc
    

;After which We Checked if Processor is a Pentium or Earlier, Let's See if
;We Are in Real Mode (https://en.wikipedia.org/wiki/Protection_ring#IOPL)
;! The RDMSR instruction must be used in Ring 0 (CR0 bit 0 = 0) ONLY !
;
; * Note: After testing, MOV EAX,CR0 not worked in Windows 3.1 Enhanced Mode!
;         So let's to use the SMSW then.
    mov    bx,ax                   ; copy cpuid maximum leaves to BX, saving his value
;    mov    eax,cr0   <---<<< NOT WORKS in Windows 3.1 Enhanced Mode!
    smsw   ax                      ; get processor Machine Status
    and    al,1                    ; processor in Protected Mode?
    jnz    Test_EMM386             ; yes, then check for EMM386.EXE presence
                                   ; and abort the execution

;Check for Time Stamp Counter Register and APERF MSR   
    push   bx                      ; save cpuid maximum leaves
    mov    eax,1
    cpuid
    test   dl,TSC_REG_FLAG         ; test if processor has a TSC register (EDX bit 4 = 1 = TSC Register OK)
    pop    ax                      ; restore cpuid maximum leaves in AL
                                   ; (allow to use the CMP AL,06 instruction
                                   ;  that is one byte smaller then CMP BL,6
                                   ;  if to use POP BX).
    jz     Bad_Proc                ; skip if processor not has a TSC register
    cmp    al,06h                  ; cpuid leaves number is 6 or greater?
    jb     Check_Invariant_TSC     ; no, then skip APERF checking (processor not support IA32_APERF MSR)
    

;Check for IA32_APERF MSR    
    mov    eax,06h
    cpuid
    and    cl,APERF_MSR_FLAG       ; check if processor has APERF MSR (CL = 1 if yes)
    mov    [CPU_HAS_APERF],cl      ; set APERF flag de acordo com o valor do cpuid flag
    jz     Check_Invariant_TSC     ; processor not has APERF. Let's go to use TSC
    mov    dx,APERF_READING_MSG
    mov    ah,09h
    int    21h                     ; show "Reading the CPU frequency through of IA32_APERF MSR..." message
    jmp    Get_CPU_Frequency


;Check if the Processor has an Invariant Time Stamp Counter
;Test only if CPUID supports 80000007h Extended Leaf
Check_Invariant_TSC:    
    mov    eax,80000000h           ; check if CPUID has Extended Leaves
    cpuid
    cmp    eax,80000007h           ; CPUID has 80000007h Extended Leaf?
    jb     Show_TSC_Reading_Msg    ; no, then skip Invariant TSC checking
    mov    eax, 0x80000007         ; check Invariant TSC presence
    cpuid
    test   dh,INVARIANT_TSC_FLAG   ; check if processor has an Invariant TSC (EDX Bit 8 = 1 = Invariant TSC present)
    jz     Show_TSC_Reading_Msg    ; no, then skip Invariant TSC message
    mov    dx,INVARIANT_TSC_MSG
    mov    ah,09h
    int    21h                     ; show "Processor has an Invariant TSC!" Message

Show_TSC_Reading_Msg:
    mov    dx,TSC_READING_MSG
    mov    ah,09h
    int    21h                     ; show "Reading the CPU frequency through of TSC register..." message


Get_CPU_Frequency:    
    mov    ah,02
    int    1Ah                     ; get current second (DH)
    call   Wait_Second_Change      ; wait the next second biggining
    push   dx                      ; save the current second
    test   byte [CPU_HAS_APERF],1
    jz     Get_Initial_TSC_Value   ; processor has not IA32_APERF
    xor    eax,eax                 ; it's good to have
    cpuid                          ; to serialize instructions (MANDATORY!)
    mov    ecx,IA32_APERF_MSR      ; load ECX with IA32_APERF (0xE8) MSR
    rdmsr
    jmp    Save_Initial_Value


Get_Initial_TSC_Value:    
    xor    eax,eax                 ; it's good to have
    cpuid                          ; to serialize instructions (MANDATORY!)
    rdtsc
    
Save_Initial_Value:    
    mov    [CLOCKS_MSDW],edx
    mov    [CLOCKS_LSDW],eax


;Wait 1 Second    
    pop    dx                      ; restore the second to check when it change (then passed 1 second)
    call   Wait_Second_Change      ; wait 1 second


;Read IA32_APERF MSR or TSC after 1 Second and Get # of Elapsed Clocks
    test   byte [CPU_HAS_APERF],1
    jz     Get_Final_TSC_Value
    xor    eax,eax                 ; it's good to have
    cpuid                          ; to serialize instructions (MANDATORY!)
    mov    ecx,IA32_APERF_MSR      ; load ECX with IA32_APERF (0xE8) MSR
    rdmsr
    jmp    Calculate_CPU_Frequency


Get_Final_TSC_Value:    
    xor    eax,eax                 ; it's good to have
    cpuid                          ; to serialize instructions (MANDATORY!)
    rdtsc


Calculate_CPU_Frequency:    
    sub    eax,[CLOCKS_LSDW]
    sbb    edx,[CLOCKS_MSDW]
    mov    ecx,1000000             ; divide by 1.000.000 to get the frequency with 4 numbers
                                   ; (1 integer and 3 decimal places for rounding purpose).
    div    ecx                     ; get frequency in format #### (#.### with a dot before of two last numbers)
    
    add    ax,5                    ; to round the second decimal place (3.996 GHz become 4.00 GHz)

;Put Decimal Frequency Value in DX    
    mov    cx,1000
    xor    dx,dx                   ; MUST CLEAR DX before of the division!
    div    cx                      ; after this, DX will have the decimal part from frequency 
    

;Convert the GHz Unity (AX) to ASCII and Store on Message Buffer   
    aam                            ; frequency unity value to BCD
    or     ax,3030h                ; BCD to ASCII
    mov    di,CPU_FREQ
    cld                            ; ensures which DI will be incremented after STOSB/STOSW
    stosb                          ; store the frequency integer value on the phrase buffer
    

;Convert GHz Decimal Value (DX) to 2 Decimal Places
;Note: DO NOT put it in 1000 division above (i.e. MOV CX,10000) because
;      that's it not works!
    mov    ax,dx                   ; copy decimal value to AX
    mov    cx,10
    xor    dx,dx                   ; MUST CLEAR DX before of the division!
    div    cx                      ; will show 2 decimal places only
    

;Convert the GHz Decimal Places to ASCII and Store on Message Buffer   
    aam                            ; frequency decimal value to BCD
    or     ax,3030h                ; BCD to ASCII
    xchg   ah,al
    inc    di                      ; skip decimal dot
    stosw                          ; store the 2 decimal places on the phrase buffer

    
;Show Processor Actual Frequency    
    mov    dx,CPU_FREQ_INFO
    mov    ah,09h
    int    21h


;Finish Successfully (Error Code 0)
    cmp    byte [DOS_VERSION],2    ; check DOS version to execute proper exit interrupt
    jb     DOS_1_EXIT              ; finish with the INT 20h (DOS 1.x)
    mov    ax,4C00h
    int    21h


;Unknown Processor or not Supported
Bad_Proc:
    mov    dx,NEED_PENTIUM_MSG
    mov    ah,09h
    int    21h
    cmp    byte [DOS_VERSION],2    ; check DOS version to execute proper exit interrupt
    jb     DOS_1_EXIT              ; finish with the INT 20h (DOS 1.x)
    mov    ax,4C01h
    int    21h                     ; finish with error code 1


;System is in Protected Mode (EMM386.EXE loaded or Windows in Enhanced Mode)
;RDMSR Instruction Can Be Executed in Ring 0 ONLY!
Test_EMM386:
    mov    ax,3567h
    int    21h                     ; checks if int 67h exists
    mov    ax,es
    or     ax,bx                   ; if 0, int 67h not exists
    jz     Not_In_Real_Mode
    
    ;Now is Safe Call Interrupt 67h
    mov    ax,0xFFA5
    mov    dx,0xFFFF
    int    67h
    cmp    ax,0x845A               ; is EMM386.EXE loaded?
    jne    Not_In_Real_Mode        ; no or not indentified
    mov    dx,EMM386_MSG           ; yes. Then show EMM386 error message and finish with error code 3
    mov    ah,09h
    int    21h
    cmp    byte [DOS_VERSION],2    ; check DOS version to execute proper exit interrupt
    jb     DOS_1_EXIT              ; finish with the INT 20h (DOS 1.x)
    mov    ax,4C03h
    int    21h                     ; finish with error code 3


;Processor in Protected Mode, but Memory Manager Not Identified or into Windows Enhanced Mode
Not_In_Real_Mode:
    mov    dx,PRIV_LEVEL_MSG
    mov    ah,09h
    int    21h
    cmp    byte [DOS_VERSION],2    ; check DOS version to execute proper exit interrupt
    jb     DOS_1_EXIT              ; finish with the INT 20h (DOS 1.x)
    mov    ax,4C02h
    int    21h                     ; finish with error code 2


;Exit for DOS 1.x Only (MS-DOS 1.x not support INT 21h 0x4C exit function)
DOS_1_EXIT:
    int    20h                     ; for DOS 1.x


;1 Second Timing
Wait_Second_Change:
    push   dx
    mov    ah,02
    int    1Ah
    pop    ax
    cmp    dx,ax  
    je     Wait_Second_Change      ; second not changed, so not passed 1 second yet
    ret


;Store DOS Version for Support Checking of INT 21h 0x4C Function
DOS_VERSION        db 0


;Store Initial APERF/TSC Value, to Compare After of 1 Second
CLOCKS_LSDW        dd 0            ; APERF or TSC value less significant double word
CLOCKS_MSDW        dd 0            ; APERF or TSC value most significant double word


;APERF Support Flag
CPU_HAS_APERF      db 0            ; flag for IA32_APERF MSR support (1 = has APERF)


;Messages
NEED_PENTIUM_MSG   db 0Dh, 0Ah, "Requires a Pentium or newer processor.", 0Dh, 0Ah, "$"
PRIV_LEVEL_MSG     db 0Dh, 0Ah, "Processor not is in Real Mode!", 0Dh, 0Ah, "$"
EMM386_MSG         db 0Dh, 0Ah, "Do not can read the processor frequency with EMM386 loaded.", 0Dh, 0Ah, "$"
INVARIANT_TSC_MSG  db 0Dh, 0Ah, "Processor has an Invariant TSC!", "$"
TSC_READING_MSG    db 0Dh, 0Ah, "Reading the CPU frequency through of TSC register...$"
APERF_READING_MSG  db 0Dh, 0Ah, "Reading the CPU frequency through of IA32_APERF MSR...$"
CPU_FREQ_INFO      db 0Dh,      "The current CPU clock speed is "
CPU_FREQ           db " .   GHz.              ", 0Dh, 0Ah, "$"


SIGNATURE          db "CPUFREQ 3 02JUN2026"
