/**
 * Defines the event of data recieved from the server.
 */
class DataEvent {
  String data;

  DataEvent(this.data);
}

class CloseEvent {
  String reason;
  CloseEvent(this.reason);
}

/**
 * Defines the event of a new connection with the server has been opened.
 */
class OpenEvent {}
