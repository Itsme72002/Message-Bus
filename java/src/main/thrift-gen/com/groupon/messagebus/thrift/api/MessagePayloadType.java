/**
 * Autogenerated by Thrift
 *
 * DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
 */
package com.groupon.messagebus.thrift.api;


import java.util.Map;
import java.util.HashMap;
import org.apache.thrift.TEnum;

public enum MessagePayloadType implements TEnum {
  JSON(1),
  BINARY(2),
  STRING(3);

  private final int value;

  private MessagePayloadType(int value) {
    this.value = value;
  }

  /**
   * Get the integer value of this enum value, as defined in the Thrift IDL.
   */
  public int getValue() {
    return value;
  }

  /**
   * Find a the enum type by its integer value, as defined in the Thrift IDL.
   * @return null if the value is not found.
   */
  public static MessagePayloadType findByValue(int value) { 
    switch (value) {
      case 1:
        return JSON;
      case 2:
        return BINARY;
      case 3:
        return STRING;
      default:
        return null;
    }
  }
}
