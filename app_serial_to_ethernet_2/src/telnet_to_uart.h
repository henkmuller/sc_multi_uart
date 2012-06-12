#ifndef __TELNET_TO_UART_H__
#define __TELNET_TO_UART_H__
#include "xccompat.h"
#include "xtcp_client.h"
#include "mutual_thread_comm.h"

void telnet_to_uart_init(chanend c_xtcp, chanend c_uart_data);

void telnet_to_uart_event_handler(chanend c_xtcp,
                                  chanend c_uart_data,
                                  REFERENCE_PARAM(xtcp_connection_t, conn));

#ifdef __XC__
select telnet_to_uart_notification_handler(chanend c_xtcp, chanend c_uart_data);
#endif

int telnet_to_uart_get_port(int id);

void telnet_to_uart_set_port(chanend c_xtcp, int id, int telnet_port);

#endif // __TELNET_TO_UART_H__

