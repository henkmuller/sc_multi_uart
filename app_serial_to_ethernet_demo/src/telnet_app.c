// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>


/*===========================================================================
 Filename: telnet_app.c
 Project : app_serial_to_ethernet_demo
 Author  : XMOS Ltd
 Version : 1v0
 Purpose : This file implements telnet extenstions required for application
 to manage telnet client data for uart channels
 -----------------------------------------------------------------------------

 ===========================================================================*/

/*---------------------------------------------------------------------------
 include files
 ---------------------------------------------------------------------------*/
#include "telnetd.h"
#include "telnet_app.h"

/*---------------------------------------------------------------------------
 constants
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 ports and clocks
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 typedefs
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 global variables
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 static variables
 ---------------------------------------------------------------------------*/
static int active_conn = -1;

/*---------------------------------------------------------------------------
 implementation
 ---------------------------------------------------------------------------*/
extern void fetch_user_data(xtcp_connection_t *conn, char data);

/** =========================================================================
 *  telnetd_new_connection
 *  set new telnet connection and send welcome message
 *
 *  \param	chanend tcp_svr	channel end sharing uip_server thread
 *  \param	int id			index to connection state member
 *  \return	None
 **/
void telnetd_new_connection(chanend tcp_svr, int id)
{
    char welcome[50] = "Welcome to serial to ethernet telnet demo!";
    telnetd_send_line(tcp_svr, id, (char *) welcome);
    active_conn = id;
}

/** =========================================================================
 *  telnetd_set_new_session
 *  Listen on the telnet port
 *  in order to receive telnet data and send it to uart via app manager
 *
 *  \param	chanend tcp_svr		channel end sharing uip_server thread
 *  \param	int 	telnet_port	telnet port number to listen
 *  \return	None
 **/
#pragma unsafe arrays
void telnetd_set_new_session(chanend tcp_svr, int telnet_port)
{
    xtcp_listen(tcp_svr, telnet_port, XTCP_PROTOCOL_TCP);
}

/** =========================================================================
 *  telnetd_connection_closed
 *  closes the active telnet connection
 *
 *  \param	chanend tcp_svr	channel end sharing uip_server thread
 *  \param	int id			index to connection state member
 *  \return	None
 **/
void telnetd_connection_closed(chanend tcp_svr, int id)
{
    active_conn = -1;
}
