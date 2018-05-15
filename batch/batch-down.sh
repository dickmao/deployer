#!/bin/bash -exu

function delete_stack {
  stack=$1
  if aws cloudformation describe-stacks --stack-name $stack 2>/dev/null ; then
      aws cloudformation delete-stack --stack-name $stack
      inprog=0
      while [ $inprog -lt 20 ] && [ "xDELETE_IN_PROGRESS" == "x$(aws cloudformation describe-stacks --stack-name $stack 2>/dev/null | jq -r ' .Stacks[0] | .StackStatus ')" ]; do
          echo DELETE_IN_PROGRESS...
          let inprog=inprog+1
          sleep 10
      done
  fi
}


delete_stack aws-batch-queues
delete_stack aws-batch
