// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/*===========================================================================
 Filename: app_manager.xc
 Project : app_serial_to_ethernet_demo
 Author  : XMOS Ltd
 Version : 1v0
 Purpose : This file implements state machine to handle http requests and
 connection state management and functionality to interface http client
 (mainly application and uart channels configuration) data
 -----------------------------------------------------------------------------

 ===========================================================================*/

/*---------------------------------------------------------------------------
 include files
 ---------------------------------------------------------------------------*/
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <xs1.h>
#include "app_manager.h"
#include "debug.h"
#include "common.h"

#define ENABLE_XSCOPE 0

#if ENABLE_XSCOPE == 1
#include <print.h>
#include <xscope.h>
#endif

/*---------------------------------------------------------------------------
 constants
 ---------------------------------------------------------------------------*/
#define	MAX_BIT_RATE					115200      //100000    //bits per sec
#define TIMER_FREQUENCY					100000000	//100 Mhz

/* Default length of a uart character in bits */
#define	DEF_CHAR_LEN					8

//#define MGR_TX_TMR_EVENT_INTERVAL		(TIMER_FREQUENCY /	\
//										(MAX_BIT_RATE * UART_TX_CHAN_COUNT))

#define MGR_TX_TMR_EVENT_INTERVAL		4000 //500
/*---------------------------------------------------------------------------
 ports and clocks
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 typedefs
 ---------------------------------------------------------------------------*/
typedef struct STRUCT_CMD_DATA
{
    //	int   flag;
    //	int   cmd_type;  //For future use
    int uart_id;
} s_pending_cmd_to_send;

/*---------------------------------------------------------------------------
 global variables
 ---------------------------------------------------------------------------*/
s_uart_channel_config uart_channel_config[UART_TX_CHAN_COUNT];
s_uart_tx_channel_fifo uart_tx_channel_state[UART_TX_CHAN_COUNT];
s_uart_rx_channel_fifo uart_rx_channel_state[UART_RX_CHAN_COUNT];
s_pending_cmd_to_send pending_cmd_to_send;
#if ENABLE_XSCOPE == 1
int gCount[UART_RX_CHAN_COUNT];
#endif //ENABLE_XSCOPE == 1

/*---------------------------------------------------------------------------
 static variables
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 implementation
 ---------------------------------------------------------------------------*/

/** =========================================================================
 *  uart_channel_init
 *
 *  Initialize Uart channels data structure
 *
 *  \param		None
 *
 *  \return		None
 *
 **/
static void uart_channel_init(void)
{
    int i;
#ifdef SET_VARIABLE_BAUD_RATE
    int baud_rate = MAX_BIT_RATE;
    int baud_rate_reset = 0;
#endif //SET_VARIABLE_BAUD_RATE
    for(i = 0; i < UART_TX_CHAN_COUNT; i++)
    {
        // Initialize Uart channels configuration data structure
        uart_channel_config[i].channel_id = i;
        uart_channel_config[i].parity = even;
        uart_channel_config[i].stop_bits = sb_1;
#ifdef SET_VARIABLE_BAUD_RATE
        uart_channel_config[i].baud = baud_rate;
#else //SET_VARIABLE_BAUD_RATE
        uart_channel_config[i].baud = MAX_BIT_RATE;
#endif //SET_VARIABLE_BAUD_RATE
        uart_channel_config[i].char_len = DEF_CHAR_LEN;
        uart_channel_config[i].polarity = start_0;
        uart_channel_config[i].telnet_port = DEF_TELNET_PORT_START_VALUE + i;

#ifdef SET_VARIABLE_BAUD_RATE
        if (1 == baud_rate_reset)
        {
            /* Reset to max baud rate for next channel */
            baud_rate = 200000;
            baud_rate_reset = 0;
        }

        baud_rate = baud_rate / 2;

        if (baud_rate < 10000)
        {
            baud_rate = 10000;
            baud_rate_reset = 1;
        }
#endif //SET_VARIABLE_BAUD_RATE
    }
}

/** =========================================================================
 *  init_uart_channel_state
 *
 *  Initialize Uart channels state to default values
 *
 *  \param			None
 *
 *  \return			None
 *
 **/
static void init_uart_channel_state(void)
{
    int i;
    /* Assumption: UART_TX_CHAN_COUNT == UART_TX_CHAN_COUNT always */
    for(i = 0; i < UART_TX_CHAN_COUNT; i++)
    {
        /* TX initialization */
        uart_tx_channel_state[i].channel_id = i;
        uart_tx_channel_state[i].pending_tx_data = FALSE;
        uart_tx_channel_state[i].read_index = 0;
        uart_tx_channel_state[i].write_index = 0;
        uart_tx_channel_state[i].buf_depth = 0;
        if(i == (UART_TX_CHAN_COUNT - 1))
        {
            /* Set last channel as currently serviced so that channel queue scan order starts from first channel */
            uart_tx_channel_state[i].is_currently_serviced = TRUE;
        }
        else
        {
            uart_tx_channel_state[i].is_currently_serviced = FALSE;
        }

        /* RX initialization */
        uart_rx_channel_state[i].channel_id = i;
        uart_rx_channel_state[i].read_index = 0;
        uart_rx_channel_state[i].write_index = 0;
        uart_rx_channel_state[i].buf_depth = 0;
        if(i == (UART_RX_CHAN_COUNT - 1))
        {
            /* Set last channel as currently serviced so that channel queue scan order starts from first channel */
            uart_rx_channel_state[i].is_currently_serviced = TRUE;
        }
        else
        {
            uart_rx_channel_state[i].is_currently_serviced = FALSE;
        }
    } //for (i=0;i<UART_TX_CHAN_COUNT;i++)
}

static void send_string_over_channel(char response[], int length, streaming chanend cWbSvr2AppMgr)
{
    int i;
    for(i = 0; i < length; i++) { cWbSvr2AppMgr <: response[i]; }
    cWbSvr2AppMgr <: MARKER_END;
}

/** =========================================================================
 *  validate_uart_params
 *  Validates UART X parameters before applying them to UART
 *
 *  \param unsigned int	Uart channel identifier
 *
 *  \return		0 		on success
 *
 **/
//static int validate_uart_params(int ui_command[], char ui_cmd_response[])
static int validate_uart_params(int ui_command[], streaming chanend cWbSvr2AppMgr)
{
    int retVal = 1; //Default Success
    int i = 0;
    int j = 0;

    /*
     *  ui_command[0] == Command type    -  ignore it for validation
     *  ui_command[1] == UART Identifier -  < UART_RX_CHAN_COUNT
     *  ui_command[2] == parity
     *  ui_command[3] == stop_bits
     *  ui_command[4] == baud
     *  ui_command[5] == char_len
     *  ui_command[6] == telnet_port
     */
    for(i = 1; ((i < NUM_UI_PARAMS) && (retVal != 0)); i++)
    {
        switch(i)
        {
            case 1:
            {
                if (ui_command[1] >= UART_RX_CHAN_COUNT)
                {
                    send_string_over_channel("Invalid UART Id", 16, cWbSvr2AppMgr);
                    retVal = 0;
                }
                /* Break validation if command is !SET*/
                if ((ui_command[0] + 48) != CMD_CONFIG_SET)
                {
                    i = NUM_UI_PARAMS; //To break looping
                }
                break;
            }
            case 2:
            {
                if ((ui_command[2] < 0) || (ui_command[2] > 4))
                {
                    send_string_over_channel("Invalid Parity Config value", 28, cWbSvr2AppMgr);
                    retVal = 0;
                }
                break;
            }
            case 3:
            {
                if ((ui_command[3] < 0) || (ui_command[3] > 1))
                {
                    send_string_over_channel("Invalid Stop Bit value", 28, cWbSvr2AppMgr);
                    retVal = 0;
                }
                break;
            }
            case 4:
            {
                if ((ui_command[4] < 150) || (ui_command[4] > UART_TX_MAX_BAUD_RATE))
                {
                    send_string_over_channel("Invalid Baud Rate value", 24, cWbSvr2AppMgr);
                    retVal = 0;
                }
                break;
            }
            case 5:
            {
                if ((ui_command[5] < 5) || (ui_command[5] > 9))
                {
                    send_string_over_channel("Invalid UART character length", 30, cWbSvr2AppMgr);
                    retVal = 0;
                }
                break;
            }
            case 6:
            {
                if ((ui_command[6] < 10) || (ui_command[6] > 65000))
                {
                    send_string_over_channel("Invalid Telnet Port", 20, cWbSvr2AppMgr);
                    retVal = 0;
                }
                else if (uart_channel_config[ui_command[1]].telnet_port != ui_command[6])
                {
                    /* For a new telnet port, check if it is already used */
                    for(j=0; j<UART_TX_CHAN_COUNT; j++)
                    {
                        if (uart_channel_config[j].telnet_port == ui_command[6])
                        {
                            send_string_over_channel("Telnet port is already in use", 30, cWbSvr2AppMgr);
                            retVal = 0;
                            break;
                        }
                    }
                }
                break;
            }
            default: break;
        } // switch(i)
    } // for(i = 1; ((i < NUM_UI_PARAMS) && (retVal != 0)); i++)
    return retVal;
}

/** =========================================================================
 *  configure_uart_channel
 *  invokes MUART component api's to initialze MUART Tx and Rx threads
 *
 *  \param unsigned int	Uart channel identifier
 *
 *  \return		0 		on success
 *
 **/
static int configure_uart_channel(unsigned int channel_id)
{
    int chnl_config_status = ERR_CHANNEL_CONFIG;
    chnl_config_status = uart_tx_initialise_channel(uart_channel_config[channel_id].channel_id,
                                                    uart_channel_config[channel_id].parity,
                                                    uart_channel_config[channel_id].stop_bits,
                                                    uart_channel_config[channel_id].polarity,
                                                    uart_channel_config[channel_id].baud,
                                                    uart_channel_config[channel_id].char_len);
    chnl_config_status |= uart_rx_initialise_channel(uart_channel_config[channel_id].channel_id,
                                                     uart_channel_config[channel_id].parity,
                                                     uart_channel_config[channel_id].stop_bits,
                                                     uart_channel_config[channel_id].polarity,
                                                     uart_channel_config[channel_id].baud,
                                                     uart_channel_config[channel_id].char_len);
    return chnl_config_status;
}

/** =========================================================================
 *  apply_default_uart_cfg_and_wait_for_muart_tx_rx_threads
 *
 *  Apply default uart channels configuration and wait for
 *  MULTI_UART_GO signal from MUART_RX and MUART_RX threads
 *
 *  \param	chanend cTxUART		channel end sharing channel to MUART TX thrd
 *
 *  \param	chanend cRxUART		channel end sharing channel to MUART RX thrd
 *
 *  \return			None
 *
 **/
static void apply_default_uart_cfg_and_wait_for_muart_tx_rx_threads(streaming chanend cTxUART,
                                                                    streaming chanend cRxUART)
{
    int channel_id;
    int chnl_config_status = 0;
    char temp;
    for(channel_id = 0; channel_id < UART_TX_CHAN_COUNT; channel_id++)
    {
        chnl_config_status = configure_uart_channel(channel_id);
        if(0 != chnl_config_status)
        {
#ifdef DEBUG_LEVEL_3
            printstr("Uart configuration failed for channel: ");
            printintln(channel_id);
#endif //DEBUG_LEVEL_3
            chnl_config_status = 0;
        }
        else
        {
#ifdef DEBUG_LEVEL_3
            printstr("Successful Uart configuration for channel: ");
            printintln(channel_id);
#endif //DEBUG_LEVEL_3
        }
    } // for(channel_id = 0; channel_id < UART_TX_CHAN_COUNT; channel_id++)
    /* Release UART rx thread */
    do { cRxUART :> temp;} while (temp != MULTI_UART_GO); cRxUART <: 1;
    /* Release UART tx thread */
    do { cTxUART :> temp;} while (temp != MULTI_UART_GO); cTxUART <: 1;
}

/** =========================================================================
 *  uart_rx_receive_uart_channel_data
 *
 *  This function waits for channel data from MUART RX thread;
 *  when uart channel data is available, decodes uart char to raw character
 *  and save the data into application managed RX buffer
 *
 *  \param chanend cUART : channel end of data channel from MUART RX thread
 *
 *  \param unsigned channel_id : uart channel identifir
 *
 *  \return			None
 *
 **/
void uart_rx_receive_uart_channel_data( streaming chanend cUART, unsigned channel_id, timer tmr)
{
    unsigned uart_char, temp;
    int write_index = 0;
    /* get character over channel */
    uart_char = (unsigned)uart_rx_grab_char(channel_id);
    /* process received value */
    temp = uart_char;
    /* validation of uart char - gives you the raw character as well */
    if(uart_rx_validate_char(channel_id, uart_char) == 0)
    {
        /* call api to fill uart data into application buffer */
        if(uart_rx_channel_state[channel_id].buf_depth < RX_CHANNEL_FIFO_LEN)
        {
            /* fill client buffer of respective uart channel */
            uart_rx_channel_state[channel_id].channel_id = channel_id;
            write_index = uart_rx_channel_state[channel_id].write_index;
            uart_rx_channel_state[channel_id].channel_data[write_index] = uart_char;
            write_index++;
            if(write_index >= RX_CHANNEL_FIFO_LEN) { write_index = 0; }
            uart_rx_channel_state[channel_id].write_index = write_index;
            uart_rx_channel_state[channel_id].buf_depth++;
            tmr :> uart_rx_channel_state[channel_id].last_added_timestamp;
        }
#if ENABLE_XSCOPE == 1
        else
        {
            for(int i=0; i<UART_RX_CHAN_COUNT; i++)
            {
            	if (i == channel_id)
            	{
            		gCount[channel_id]++;
            		break;
            	}
            }

            if (500 == gCount[channel_id])
        	{
        		gCount[channel_id] = 0;
            	printintln(channel_id);
        	}
            //printstr("App uart RX buffer full. Missed char for chnl id: ");
            //printintln(channel_id);
        }
#endif	//DEBUG_LEVEL_2
    } // if(uart_rx_validate_char(channel_id, uart_char) == 0)
}

/** =========================================================================
 *  get_uart_channel_data
 *
 *  This function waits for channel data from MUART RX thread;
 *  when uart channel data is available, decodes uart char to raw character
 *  and save the data into application managed RX buffer
 *
 *  \param int channel_id : reference to uart channel identifir
 *
 *  \param int conn_id 	 : reference to client connection identifir
 *
 *  \param int read_index : reference to current buffer position to read
 *  							channel data
 *
 *  \param int buf_depth : reference to current depth of uart channel buffer
 *
 *  \return			1	when there is data to send
 *  					0	otherwise
 *
 **/
static void poll_uart_rx_data_to_send_to_client(chanend cAppMgr2WbSvr, timer tmr)
{
    int channel_id = 0;
    int temp_channel_id = 0;
    int channel_iter = 0;
    int now;
    int min_buf_level;
    for(channel_id = 0; channel_id < UART_RX_CHAN_COUNT; channel_id++)
    {
        if(TRUE == uart_rx_channel_state[channel_id].is_currently_serviced) break;
    }

    /* 'channel_id' now contains channel queue # that is just serviced
     * reset it and increment to point to next channel */
    uart_rx_channel_state[channel_id].is_currently_serviced = FALSE;
    channel_id++;

    if(channel_id >= UART_RX_CHAN_COUNT)
    {
        channel_id = 0;
    }
    uart_rx_channel_state[channel_id].is_currently_serviced = TRUE;

    /* In general we do not want to send less that RX_CHANNEL_MIN_PACKET_LEN
     bytes to the tcp handling thread.
     However, in some cases there may be a small amount of data left in
     the fifo followed by no activity. In this case we check for a
     timeout and then send anything left in the fifo
     */
    tmr :> now;
    if timeafter(now, uart_rx_channel_state[channel_id].last_added_timestamp + RX_CHANNEL_FLUSH_TIMEOUT)
    {
        min_buf_level = 0;
    }
    else
    {
    	if (uart_channel_config[channel_id].baud > 57600)
    		min_buf_level = RX_CHANNEL_MIN_PACKET_LEN;
    	else
    		min_buf_level = RX_CHANNEL_MIN_PACKET_LEN_DEFAULT;
    }

    if ((uart_rx_channel_state[channel_id].buf_depth > min_buf_level) && (uart_rx_channel_state[channel_id].buf_depth <= RX_CHANNEL_FIFO_LEN))
    {
        /* Send Uart Id and buffer depth */
        outct(cAppMgr2WbSvr, '3'); //UART_DATA_READY_UART_TO_APP
        cAppMgr2WbSvr <: channel_id;
        return;
    }
    else
    {
    	temp_channel_id = channel_id;
    	/* Loop for all other channels to check if there is any data available on any other channel */
    	for(channel_iter = 0; channel_iter < UART_RX_CHAN_COUNT; channel_iter++)
    	{
    		temp_channel_id++;

    	    if(temp_channel_id >= UART_RX_CHAN_COUNT)
    	    {
    	    	temp_channel_id = 0;
    	    }

    	    if (temp_channel_id != channel_id)
    	    {
    	        tmr :> now;
    	        if timeafter(now, uart_rx_channel_state[temp_channel_id].last_added_timestamp + RX_CHANNEL_FLUSH_TIMEOUT)
    	        {
    	            min_buf_level = 0;
    }
    else
    	        {
    	        	if (uart_channel_config[temp_channel_id].baud > 57600)
    	        		min_buf_level = RX_CHANNEL_MIN_PACKET_LEN;
    	        	else
    	        		min_buf_level = RX_CHANNEL_MIN_PACKET_LEN_DEFAULT;
    	        }

    	        if ((uart_rx_channel_state[temp_channel_id].buf_depth > min_buf_level) && (uart_rx_channel_state[temp_channel_id].buf_depth <= RX_CHANNEL_FIFO_LEN))
    	        {
    	            /* Send Uart Id and buffer depth */
    	            outct(cAppMgr2WbSvr, '3'); //UART_DATA_READY_UART_TO_APP
    	            cAppMgr2WbSvr <: temp_channel_id;

    	            uart_rx_channel_state[channel_id].is_currently_serviced = FALSE;
    	            uart_rx_channel_state[temp_channel_id].is_currently_serviced = TRUE;
    	            return;
    	        }
    	    }
    	}
    }

    /* This will be called when there is no UART data in any of the UART Channels */
    outct(cAppMgr2WbSvr, '4'); //NO_UART_DATA_READY
}

/** =========================================================================
 *  collect_uart_tx_data
 *
 *  This function collects xtcp telnet data into application buffer
 *
 *  \param chanend cAppMgr2WbSvr : Channel to exchange telnet data
 *
 *  \return			None
 *
 **/
static void collect_uart_tx_data(chanend cAppMgr2WbSvr)
{
    int buf_depth_available = -1;
    int i = 0;
    int channel_id = -1;
    char chan_data;

    cAppMgr2WbSvr :> channel_id;
    buf_depth_available = TX_CHANNEL_FIFO_LEN - uart_tx_channel_state[channel_id].buf_depth;
    cAppMgr2WbSvr <: buf_depth_available;
    cAppMgr2WbSvr :> buf_depth_available; //This now contains only required buf depth to send

    for (i = 0; i < buf_depth_available; i++)
    {
        cAppMgr2WbSvr :> chan_data;
        uart_tx_channel_state[channel_id].channel_data[uart_tx_channel_state[channel_id].write_index] = (char)chan_data;
        uart_tx_channel_state[channel_id].write_index++;
        if (uart_tx_channel_state[channel_id].write_index >= TX_CHANNEL_FIFO_LEN) { uart_tx_channel_state[channel_id].write_index = 0; }
        uart_tx_channel_state[channel_id].buf_depth++;
    }
}

/** =========================================================================
 *  uart_rx_send_uart_channel_data
 *
 *  This function waits for channel data from MUART RX thread;
 *  when uart channel data is available, decodes uart char to raw character
 *  and save the data into application managed RX buffer
 *
 *  \param int channel_id : reference to uart channel identifir
 *
 *  \param int conn_id 	 : reference to client connection identifir
 *
 *  \param int read_index : reference to current buffer position to read
 *  							channel data
 *
 *  \param int buf_depth : reference to current depth of uart channel buffer
 *
 *  \return			1	when there is data to send
 *  					0	otherwise
 *
 **/
static void uart_rx_send_uart_channel_data(chanend cAppMgr2WbSvr)
{
    int i = 0;
    int local_read_index = 0;

    int channel_id = 0;
    int read_index = 0;
    unsigned int buf_depth = 0;
    char buffer[] = "";

    cAppMgr2WbSvr :> channel_id;
    read_index = uart_rx_channel_state[channel_id].read_index;
    buf_depth = uart_rx_channel_state[channel_id].buf_depth;

    /* Send Uart X buffer depth */
    cAppMgr2WbSvr <: buf_depth;
    local_read_index = read_index; // TODO: Bug: Data for chnl 7 is always present

    for (i=0; i<buf_depth; i++)
    {
        /* Send Uart X data over channel */
        cAppMgr2WbSvr <: uart_rx_channel_state[channel_id].channel_data[local_read_index];
        local_read_index++;
        if (local_read_index >= RX_CHANNEL_FIFO_LEN) { local_read_index = 0; }
    }

    /* Data is pushed to app manager thread; Update buffer state pointers */
    read_index += buf_depth;
    if (read_index > (RX_CHANNEL_FIFO_LEN-1)) { read_index -= RX_CHANNEL_FIFO_LEN; }
    uart_rx_channel_state[channel_id].read_index = read_index;
    uart_rx_channel_state[channel_id].buf_depth -= buf_depth; //= 0;
}

/** =========================================================================
 *  uart_tx_fill_uart_channel_data_from_queue
 *
 *  This function primarily handles UART TX buffer overflow condition by
 *  storing data into its application buffer when UART Tx buffer is full
 *  This function reads data from uart channel specific application TX buffer
 *  and invokes MUART TX api to send to uart channel of MUART TX component
 *
 *  \param 			None
 *
 *  \return			None
 *
 **/
void uart_tx_fill_uart_channel_data_from_queue()
{
    int channel_id;
    int buffer_space = 0;
    char data;
    int read_index = 0;

    for(channel_id = 0; channel_id < UART_TX_CHAN_COUNT; channel_id++)
    {
        if(TRUE == uart_tx_channel_state[channel_id].is_currently_serviced) break;
    }

    /* 'channel_id' now contains channel queue # that is just serviced
     * reset it and increment to point to next channel */
    uart_tx_channel_state[channel_id].is_currently_serviced = FALSE;
    channel_id++;
    if(channel_id >= UART_TX_CHAN_COUNT) { channel_id = 0; }
    uart_tx_channel_state[channel_id].is_currently_serviced = TRUE;
    if((uart_tx_channel_state[channel_id].buf_depth > 0) && (uart_tx_channel_state[channel_id].buf_depth <= TX_CHANNEL_FIFO_LEN))
    {
        read_index = uart_tx_channel_state[channel_id].read_index;
        data = uart_tx_channel_state[channel_id].channel_data[read_index];
        /* There is pending Uart buffer data */
        /* Try to transmit to uart directly */
        buffer_space = uart_tx_put_char(channel_id, (unsigned int)data);
        if(-1 != buffer_space)
        {
            /* Data is pushed to uart successfully */
            read_index++;
            if(read_index >= TX_CHANNEL_FIFO_LEN) { read_index = 0; }
            uart_tx_channel_state[channel_id].read_index = read_index;
            uart_tx_channel_state[channel_id].buf_depth--;
        } // if(-1 != buffer_space)
    } // if((uart_tx_channel_state[channel_id].buf_depth > 0) && (uart_tx_channel_state[channel_id].buf_depth <= TX_CHANNEL_FIFO_LEN))
}

/** =========================================================================
 *  re_apply_uart_channel_config
 *
 *  This function either configures or reconfigures a uart channel
 *
 *  \param	s_uart_channel_config sUartChannelConfig Reference to UART conf
 *
 *  \param	chanend cTxUART		channel end sharing channel to MUART TX thrd
 *
 *  \param	chanend cRxUART		channel end sharing channel to MUART RX thrd
 *
 *  \return			None
 *
 **/
#pragma unsafe arrays
static int re_apply_uart_channel_config(int channel_id,
                                        streaming chanend cTxUART,
                                        streaming chanend cRxUART)
{
    int ret_val = 0;
    int chnl_config_status = 0;
    timer t;

    uart_tx_reconf_pause(cTxUART, t);
    uart_rx_reconf_pause(cRxUART);
    chnl_config_status = configure_uart_channel(channel_id);
    uart_tx_reconf_enable(cTxUART);
    uart_rx_reconf_enable(cRxUART);
    /*
    if(0 != chnl_config_status)
    {
        printint(channel_id);
        printstrln(": Channel reconfig failed");
    }
    */
    //TODO: Send response back on the channel
}

/** =========================================================================
 *  parse_uart_command_data
 *
 *  This function parses UI command data to identify different UART params
 *
 *  \param	chanend cWbSvr2AppMgr channel end sharing web server thread
 *
 *  \return			None
 *
 **/
static int parse_uart_command_data( streaming chanend cWbSvr2AppMgr,
                                   streaming chanend cTxUART,
                                   streaming chanend cRxUART)
{
    char ui_cmd_unparsed[UI_COMMAND_LENGTH];
    char ui_cmd_response[UI_COMMAND_LENGTH]; //TODO; Chk if this can be optimized
    int ui_command[NUM_UI_PARAMS];
    int cmd_length = 0;
    char cmd_type;

    int i, j;
    int iTemp = 0;
    char dv[20]; //
    int index_start = 0;
    int index_end = 0;
    int index_cfg = -1;
    int index_uart = 0;
    char ui_param[20];

    /* Get UART command data */
    {
        int done = 0;
        int i = 0;

        do
        {
            cWbSvr2AppMgr :> ui_cmd_unparsed[i];
            if(ui_cmd_unparsed[i] == MARKER_END)
            {
                done = 1;
            }
            else
            {
                i++;
            }
        } while(done == 0);
        cmd_length = i;
    }

    // Get the variables
    for (i = 0; i < cmd_length; i++)
    {
        if (ui_cmd_unparsed[i] == MARKER_START)
        {
            if (index_end == 0)
            {
                index_cfg++;
                index_end = i + 1;
                index_start = i + 1;
            } // if(index_end == 0)
            else
            {
                // clear
                ui_cmd_unparsed[index_cfg] = 0;
                /* Clear the array */
                for (iTemp = 0; iTemp < 20; iTemp++)
                {
                    dv[iTemp] = '\0';
                }

                for (j = 0; j < (i - index_start); j++)
                {
                    dv[j] = ui_cmd_unparsed[j + index_start];
                }

                ui_command[index_cfg] = atoi(dv);
                index_end = 0;
                index_start = 0;
            } //else [if (index_end == 0)]
        } //if (ui_cmd_unparsed[i] == '~')
    } //for (i = 0; i < cmd_length; i++)

    // Now process the Command request
    //if (validate_uart_params(ui_command, ui_cmd_response) //TODO
    if (validate_uart_params(ui_command, cWbSvr2AppMgr))
    {
        cmd_type = ui_command[0] + 48; // +48 for char
        index_uart = ui_command[1]; //UART channel identifier

        if (CMD_CONFIG_GET == cmd_type)
        {
            // Get settings and store it in config_structure array
            // config_structure = s_uart_channel_config.abc
            ui_command[2] = uart_channel_config[index_uart].parity;
            ui_command[3] = uart_channel_config[index_uart].stop_bits;
            ui_command[4] = uart_channel_config[index_uart].baud;
            ui_command[5] = uart_channel_config[index_uart].char_len;
            //Parameter 'Polarity' is not yet part of UI
            ui_command[6] = uart_channel_config[index_uart].telnet_port;
        }
        else if (CMD_CONFIG_SET == cmd_type)
        {
            // Set configuration from the data available in config_structure
            uart_channel_config[index_uart].channel_id = ui_command[1];
            uart_channel_config[index_uart].parity = ui_command[2];
            uart_channel_config[index_uart].stop_bits = ui_command[3];
            uart_channel_config[index_uart].baud = ui_command[4];
            uart_channel_config[index_uart].char_len = ui_command[5];
            uart_channel_config[index_uart].telnet_port = ui_command[6];

            re_apply_uart_channel_config(index_uart, cTxUART, cRxUART);
            //TODO: Channel backup may be required and need to be reconfigured upon failure
            //pending_cmd_to_send.cmd_type = ui_command[0];
            pending_cmd_to_send.uart_id = ui_command[1]; //UART Id
        }

        /* Form response and send it back to channel */
        for (i = 0; i < NUM_UI_PARAMS; i++)
        {
            j = 0;
            cWbSvr2AppMgr <: MARKER_START;
            if (0 != ui_command[i])
            {
                while(0 != ui_command[i])
                {
                    ui_param[j] = ui_command[i]%10;
                    ui_command[i] = ui_command[i]/10;
                    j++;
                }
                while(0 != j)
                {
                    cWbSvr2AppMgr <: (char)(ui_param[j-1] + 48);
                    j--;
                }
            }
            else
            {
                cWbSvr2AppMgr <: (char)(ui_command[i] + 48);
            }
            cWbSvr2AppMgr <: MARKER_START;
        }
        cWbSvr2AppMgr <: MARKER_END;
    }
}

/** 
 *  The multi uart manager thread. This thread
 *  (i) periodically polls for data on application Tx buffer, in order to transmit to telnet clients
 *  (ii) waits for channel data from MUART Rx thread
 *
 *  \param	chanend cWbSvr2AppMgr channel end sharing web server thread
 *  \param	chanend cTxUART		channel end sharing channel to MUART TX thrd
 *  \param	chanend cRxUART		channel end sharing channel to MUART RX thrd
 *  \return	None
 *
 */
void app_manager_handle_uart_data( streaming chanend cWbSvr2AppMgr,
                                  chanend cAppMgr2WbSvr,
                                  streaming chanend cTxUART,
                                  streaming chanend cRxUART)
{
    timer txTimer;
    unsigned txTimeStamp;
    char rx_channel_id;
    unsigned int local_port = 0;
    int conn_id = 0;
    int WbSvr2AppMgr_chnl_data = 9999;
    char flash_config_valid;
    int i;
    char flash_data;
    unsigned char tok;
    int write_index;

#if ENABLE_XSCOPE == 1
    xscope_register(0, 0, "", 0, "");
    xscope_config_io(XSCOPE_IO_BASIC);
#endif

    //TODO: Flash cold start should happen here
    /* Applying default in-program values, in case Cold start fails */
    uart_channel_init();

    for(i = 0; i < UART_TX_CHAN_COUNT; i++)
    {
        /* Send uart key data to app server */
        cWbSvr2AppMgr <: uart_channel_config[i].channel_id;
    }

    init_uart_channel_state();
    apply_default_uart_cfg_and_wait_for_muart_tx_rx_threads( cTxUART, cRxUART);
    txTimer :> txTimeStamp;
    txTimeStamp += MGR_TX_TMR_EVENT_INTERVAL;

    // Loop forever processing Tx and Rx channel data
    while(1)
    {
        select
        {
#pragma ordered
#pragma xta endpoint "ep_1"
            case cRxUART :> rx_channel_id:
            {
                //Read data from MUART RX thread
                uart_rx_receive_uart_channel_data(cRxUART, rx_channel_id, txTimer);
                break;
            }

            case inct_byref(cAppMgr2WbSvr, tok):
            {
                /* Check for any UART data poll request from WS */
                if ('1' == tok)
                {
                    poll_uart_rx_data_to_send_to_client(cAppMgr2WbSvr, txTimer);
                }
                else if ('2' == tok)
                {
                    //Send data from App RX queue
                    uart_rx_send_uart_channel_data(cAppMgr2WbSvr);
                }
                else if ('A' == tok) //UART_DATA_READY_FROM_APP_TO_UART

                {
                    collect_uart_tx_data(cAppMgr2WbSvr); //UART_DATA_FROM_APP_TO_UART
                }
                break;
            }

            case cWbSvr2AppMgr :> WbSvr2AppMgr_chnl_data :
            {
                if (UART_CMD_FROM_APP_TO_UART == WbSvr2AppMgr_chnl_data)
                {
                    /* This is a UART command. Parse to get command type and process accordingly */
                    parse_uart_command_data(cWbSvr2AppMgr, cTxUART, cRxUART);
                }
                else if (UART_SET_END_FROM_APP_TO_UART == WbSvr2AppMgr_chnl_data)
                {
                    cWbSvr2AppMgr <: UART_CMD_MODIFY_TLNT_PORT_FROM_UART_TO_APP;
                    cWbSvr2AppMgr <: pending_cmd_to_send.uart_id;
                    cWbSvr2AppMgr <: uart_channel_config[pending_cmd_to_send.uart_id].telnet_port;
                }
                else if (UART_RESTORE_END_FROM_APP_TO_UART == WbSvr2AppMgr_chnl_data)
                {
                    /* Send all telnet port numbers to App server */
                    cWbSvr2AppMgr <: UART_CMD_MODIFY_ALL_TLNT_PORTS_FROM_UART_TO_APP;
                    for(i = 0; i < UART_TX_CHAN_COUNT; i++)
                    {
                        /* Send uart key data to app server */
                        cWbSvr2AppMgr <: uart_channel_config[i].channel_id;
                        cWbSvr2AppMgr <: uart_channel_config[i].telnet_port;
                    }
                }
                break;
            }

            case txTimer when timerafter (txTimeStamp) :> void:
            {
                //Read data from App TX queue
                uart_tx_fill_uart_channel_data_from_queue();
                txTimeStamp += MGR_TX_TMR_EVENT_INTERVAL;
                break;
            }

            default: break;
        } // select
    } // while(1)
}

//#pragma xta command "analyze function uart_rx_receive_uart_channel_data"
